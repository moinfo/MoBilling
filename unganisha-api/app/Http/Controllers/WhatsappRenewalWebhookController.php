<?php

namespace App\Http\Controllers;

use App\Exceptions\CouponUnavailableException;
use App\Helpers\PhoneHelper;
use App\Models\Client;
use App\Models\Coupon;
use App\Models\Document;
use App\Models\Domain;
use App\Models\DomainTld;
use App\Models\HostingAccount;
use App\Models\MosmsAccount;
use App\Models\PesapalInvoicePayment;
use App\Models\ProductService;
use App\Models\Server;
use App\Models\Tenant;
use App\Models\User;
use App\Models\WhatsappRenewalSession;
use App\Services\CouponService;
use App\Services\DocumentNumberService;
use App\Services\Hosting\RenewalBundleService;
use App\Services\Registrar\DomainRegistrarManager;
use App\Services\TenantPesapalService;
use App\Services\TznicWhoisService;
use App\Services\WhatsAppService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

/**
 * MoSMS forwards two kinds of WhatsApp self-service signals here (see
 * MoSMS's WhatsAppWebhookController::handleMobillingRenewalReply()/
 * handleMobillingMenuMessage()):
 *  - confirm(): a bare "1" reply to a specific domain-expiry reminder
 *    (whatsapp_renewal_sessions written by SendDomainExpiryReminders).
 *  - menu(): any other message from a phone MoSMS's shared number most
 *    recently sent something to on Moinfotech's behalf — the general
 *    self-service catch-all (language select, root menu: renewals, new
 *    domain/hosting orders, unpaid invoices, WHOIS, availability check).
 *
 * Every message is bilingual (en/sw) — see t(). A client picks a language
 * once, at the very start of a conversation, via startLanguageSelect();
 * it's remembered on the session (like the surname-verified identity) for
 * as long as that session lives, and re-asked only after a fresh contact
 * or an explicit logout.
 *
 * Public, no Laravel auth — guarded by a shared secret, mirroring MoSMS's
 * own mopos debt-confirmation callback.
 */
class WhatsappRenewalWebhookController extends Controller
{
    /** Marker-triggered: MoSMS already knows this was a bare "1" to a specific reminder. */
    public function confirm(Request $request, RenewalBundleService $bundler)
    {
        $request->validate([
            'secret' => 'required|string',
            'mosms_tenant_id' => 'required',
            'phone' => 'required|string',
        ]);

        [$tenant, $account] = $this->authenticate($request);
        if (!$tenant) {
            return response('OK', 200);
        }

        $phone = PhoneHelper::normalize($request->phone);

        $session = WhatsappRenewalSession::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->where('phone', $phone)
            ->first();

        if (!$session || $session->isExpired() || empty($session->items)) {
            $lang = $session->language ?? 'sw';
            $this->reply($tenant, $phone, $this->t($lang,
                'Samahani, muda wa kujibu umepita. Tafadhali wasiliana nasi au ingia kwenye client portal kufanya renewal.',
                'Sorry, the reply window has passed. Please contact us or log in to the client portal to renew.'
            ));
            return response('OK', 200);
        }

        $this->pickAndGenerate($tenant, null, $phone, $session, 1, $bundler, $session->language ?? 'sw');

        return response('OK', 200);
    }

    /**
     * Catch-all: any other message from a phone MoSMS believes belongs to
     * this tenant's conversation. Routes to whichever step-machine the
     * client's current session is in (see the private handle*Step methods),
     * or — freshly confirmed / at the root — the top-level self-service menu.
     */
    public function menu(Request $request, RenewalBundleService $bundler)
    {
        $request->validate([
            'secret' => 'required|string',
            'mosms_tenant_id' => 'required',
            'phone' => 'required|string',
            'text' => 'nullable|string',
        ]);

        [$tenant, $account] = $this->authenticate($request);
        if (!$tenant) {
            return response('OK', 200);
        }

        $phone = PhoneHelper::normalize($request->phone);
        $text = trim((string) $request->input('text', ''));

        $session = WhatsappRenewalSession::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->where('phone', $phone)
            ->first();

        // Staff-assist: a staff member's OWN phone helping a client, not the client's own
        // self-service. Checked before anything else — STAFF always wins over whatever this
        // phone's session state happens to be, same as MoSMS's cold-start keywords.
        if ($session && !$session->isExpired() && in_array($session->flow, ['staff_pin', 'staff_menu', 'staff_search'], true)) {
            $this->handleStaffAssistStep($tenant, $phone, $session, $text);
            return response('OK', 200);
        }

        if (preg_match('/^\s*(staff|wafanyakazi)\s*$/i', $text)) {
            $this->startStaffAssist($tenant, $phone);
            return response('OK', 200);
        }

        if ($session && !$session->isExpired() && $session->flow === 'language_select') {
            $this->handleLanguageStep($tenant, $phone, $session, $text);
            return response('OK', 200);
        }

        if ($session && !$session->isExpired() && $session->flow === 'register') {
            $this->handleRegistrationStep($tenant, $phone, $session, $text);
            return response('OK', 200);
        }

        if ($session && !$session->isExpired() && $session->confirmed_at) {
            $lang = $session->language ?? 'sw';
            $client = Client::withoutGlobalScopes()->whereNull('deleted_at')->find($session->client_id);
            if (!$client) {
                $session->delete();
                $this->reply($tenant, $phone, $this->t($lang, 'Samahani, kuna hitilafu. Tafadhali wasiliana nasi.', 'Sorry, something went wrong. Please contact us.'));
                return response('OK', 200);
            }

            // Universal escape — works from any step of any flow, not just the root
            // menu's own "unrecognised input" fallback, so someone stuck mid-order
            // always has a way back out without waiting for the session to expire.
            if ($session->flow && preg_match('/^\s*(menu|cancel|nyumbani|anza\s*upya)\s*$/i', $text)) {
                $this->sendRootMenu($tenant, $client, $phone, $lang);
                return response('OK', 200);
            }

            match ($session->flow) {
                'order_domain' => $this->handleOrderDomainStep($tenant, $client, $phone, $session, $text, $lang),
                'order_hosting' => $this->handleOrderHostingStep($tenant, $client, $phone, $session, $text, $lang),
                'pay_invoice' => $this->handlePayInvoiceStep($tenant, $client, $phone, $session, $text, $lang),
                'whois' => $this->handleWhoisStep($tenant, $client, $phone, $session, $text, $lang),
                'check_availability' => $this->handleCheckAvailabilityStep($tenant, $client, $phone, $session, $text, $lang),
                'change_dns' => $this->handleChangeDnsStep($tenant, $client, $phone, $session, $text, $lang),
                'hosting_submenu' => $this->handleHostingSubmenuStep($tenant, $client, $phone, $session, $text, $lang),
                'hosting_manage' => $this->handleHostingManageStep($tenant, $client, $phone, $session, $text, $lang),
                default => $this->handleRootStep($tenant, $client, $phone, $session, $text, $bundler, $lang),
            };

            return response('OK', 200);
        }

        if ($session && !$session->isExpired() && !$session->confirmed_at) {
            $this->handleSurnameStep($tenant, $phone, $session, $text);
            return response('OK', 200);
        }

        $clientMatch = Client::withoutGlobalScopes()->whereNull('deleted_at')->where('tenant_id', $tenant->id);
        $clientMatch = PhoneHelper::wherePhone($clientMatch, 'phone', $phone)->first();

        // Every fresh contact picks a language first — mirrors the DStv-style bot the
        // user pointed to — before anything else (registration or identity
        // verification) happens, in either language from that point on.
        $this->startLanguageSelect($tenant, $phone, $clientMatch);

        return response('OK', 200);
    }

    // ── Staff assist (own phone, helping a client) ──────────────────────
    // Reuses WhatsappRenewalSession entirely — once a client is picked, the session looks
    // exactly like that client's own confirmed session (client_id set, confirmed_at set),
    // just with assisted_by_user_id also set, so every downstream flow (order, pay, DNS,
    // WHOIS...) already works unchanged. Phone-match against User.phone has no second factor
    // on its own — same gap already fixed for client and MoSMS self-service — so a PIN gates
    // it, mirroring MoSMS's own PIN gate exactly.

    private const MAX_STAFF_PIN_ATTEMPTS = 3;

    private function startStaffAssist(Tenant $tenant, string $phone): void
    {
        $staffMatch = User::withoutGlobalScopes()->where('tenant_id', $tenant->id)->where('is_active', true);
        $staff = PhoneHelper::wherePhone($staffMatch, 'phone', $phone)->first();

        if (!$staff) {
            $this->reply($tenant, $phone, 'Namba hii haijasajiliwa kama mfanyakazi wa ' . $tenant->name . '. Wasiliana na msimamizi wako.');
            return;
        }

        $step = $staff->whatsapp_pin_hash ? 'enter_pin' : 'set_pin_1';

        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => null, 'assisted_by_user_id' => $staff->id, 'flow' => 'staff_pin', 'language' => null,
                'state' => ['step' => $step, 'staff_id' => $staff->id, 'attempts' => 0], 'items' => null,
                'confirmed_at' => null, 'expires_at' => now()->addMinutes(10)],
        );

        $this->reply($tenant, $phone, $step === 'enter_pin'
            ? "Habari {$staff->name}! Kwa usalama, andika PIN yako ya namba 4 (au andika BADILISHA kuibadilisha)."
            : "Habari {$staff->name}! Kwa usalama wa hali ya 'staff assist', tengeneza PIN ya namba 4 (mfano: 1234). Andika PIN mpya.");
    }

    private function handleStaffAssistStep(Tenant $tenant, string $phone, WhatsappRenewalSession $session, string $text): void
    {
        $state = $session->state ?? [];
        $staff = User::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($state['staff_id'] ?? null);
        if (!$staff) {
            $session->delete();
            $this->reply($tenant, $phone, 'Samahani, kuna hitilafu. Tafadhali jaribu tena.');
            return;
        }

        // Universal exit from staff-assist mode entirely (not just back to the staff menu) —
        // deletes the session, same as a client's own logout().
        if (preg_match('/^\s*(menu|toka|cancel)\s*$/i', $text) && $session->flow !== 'staff_pin') {
            $session->delete();
            $this->reply($tenant, $phone, 'Umetoka kwenye hali ya staff-assist. Andika STAFF wakati wowote kuingia tena.');
            return;
        }

        $step = $state['step'] ?? null;

        if ($session->flow === 'staff_pin') {
            if ($step === 'set_pin_1') {
                if (!preg_match('/^\d{4}$/', trim($text))) {
                    $this->reply($tenant, $phone, 'PIN lazima iwe namba 4 (mfano: 1234). Jaribu tena.');
                    return;
                }
                $session->update(['state' => array_merge($state, ['step' => 'set_pin_2', 'pin1' => trim($text)])]);
                $this->reply($tenant, $phone, 'Rudia PIN hiyo hiyo kuthibitisha.');
                return;
            }

            if ($step === 'set_pin_2') {
                if (trim($text) !== ($state['pin1'] ?? null)) {
                    $session->update(['state' => array_merge($state, ['step' => 'set_pin_1'])]);
                    $this->reply($tenant, $phone, 'PIN hazifanani. Andika PIN mpya ya namba 4.');
                    return;
                }
                $staff->update(['whatsapp_pin_hash' => Hash::make(trim($text))]);
                $this->reply($tenant, $phone, 'PIN imewekwa!');
                $this->startStaffMenu($tenant, $phone, $session, $staff);
                return;
            }

            if ($step === 'enter_pin') {
                if (preg_match('/^\s*(badilisha|change)\s*$/i', $text)) {
                    $session->update(['state' => array_merge($state, ['step' => 'change_verify_old'])]);
                    $this->reply($tenant, $phone, 'Andika PIN yako ya SASA kuthibitisha.');
                    return;
                }

                if (!Hash::check(trim($text), $staff->whatsapp_pin_hash)) {
                    $attempts = ((int) ($state['attempts'] ?? 0)) + 1;
                    if ($attempts >= self::MAX_STAFF_PIN_ATTEMPTS) {
                        $session->delete();
                        $this->reply($tenant, $phone, 'PIN si sahihi mara kadhaa. Kwa usalama, jaribu tena baadaye (andika STAFF).');
                        return;
                    }
                    $session->update(['state' => array_merge($state, ['attempts' => $attempts])]);
                    $this->reply($tenant, $phone, "PIN si sahihi. Jaribu tena ({$attempts}/" . self::MAX_STAFF_PIN_ATTEMPTS . ').');
                    return;
                }
                $this->startStaffMenu($tenant, $phone, $session, $staff);
                return;
            }

            // Re-verify the OLD PIN before allowing a change, then fall straight into the
            // existing set_pin_1/set_pin_2 steps to collect the new one — no separate logic
            // needed, they already hash+save+continue to client search on success.
            if ($step === 'change_verify_old') {
                if (!Hash::check(trim($text), $staff->whatsapp_pin_hash)) {
                    $attempts = ((int) ($state['attempts'] ?? 0)) + 1;
                    if ($attempts >= self::MAX_STAFF_PIN_ATTEMPTS) {
                        $session->delete();
                        $this->reply($tenant, $phone, 'PIN si sahihi mara kadhaa. Kwa usalama, jaribu tena baadaye (andika STAFF).');
                        return;
                    }
                    $session->update(['state' => array_merge($state, ['attempts' => $attempts])]);
                    $this->reply($tenant, $phone, "PIN si sahihi. Jaribu tena ({$attempts}/" . self::MAX_STAFF_PIN_ATTEMPTS . ').');
                    return;
                }
                $session->update(['state' => array_merge($state, ['step' => 'set_pin_1'])]);
                $this->reply($tenant, $phone, 'Andika PIN mpya ya namba 4.');
                return;
            }
        }

        if ($session->flow === 'staff_menu') {
            if (preg_match('/^\s*1\s*$/', $text)) {
                $this->sendStaffFollowups($tenant, $phone, $staff);
                $this->startStaffMenu($tenant, $phone, $session, $staff);
                return;
            }
            if (preg_match('/^\s*2\s*$/', $text)) {
                $this->startStaffClientSearch($tenant, $phone, $session, $staff);
                return;
            }
            $this->reply($tenant, $phone, 'Samahani, jibu 1 au 2.');
            $this->startStaffMenu($tenant, $phone, $session, $staff);
            return;
        }

        if ($session->flow === 'staff_search') {
            if (($state['step'] ?? null) === 'pick_client' && preg_match('/^\s*([1-9])\s*$/', $text, $m) && !empty($state['match_ids'][$m[1] - 1])) {
                $client = Client::withoutGlobalScopes()->whereNull('deleted_at')->where('tenant_id', $tenant->id)->find($state['match_ids'][$m[1] - 1]);
                if (!$client) {
                    $this->reply($tenant, $phone, 'Samahani, mteja huyo hapatikani tena. Andika jina/email/namba upya.');
                    $session->update(['state' => array_merge($state, ['step' => 'search'])]);
                    return;
                }
                $this->confirmStaffAssist($tenant, $phone, $session, $staff, $client);
                return;
            }

            $query = trim($text);
            if ($query === '') {
                $this->reply($tenant, $phone, 'Andika jina, email, au namba ya simu ya mteja.');
                return;
            }

            $matches = $this->searchClientsForStaff($tenant, $query);

            if ($matches->isEmpty()) {
                $this->reply($tenant, $phone, "Hakuna mteja aliyepatikana kwa \"{$query}\". Jaribu jina, email, au namba nyingine.");
                return;
            }

            if ($matches->count() === 1) {
                $this->confirmStaffAssist($tenant, $phone, $session, $staff, $matches->first());
                return;
            }

            $lines = ["Wateja " . $matches->count() . " wamepatikana kwa \"{$query}\":"];
            $ids = [];
            foreach ($matches->take(9) as $i => $c) {
                $ids[] = $c->id;
                $lines[] = ($i + 1) . ") {$c->name}" . ($c->phone ? " — {$c->phone}" : '');
            }
            $session->update(['state' => array_merge($state, ['step' => 'pick_client', 'match_ids' => $ids])]);
            $lines[] = "\nJibu na namba kumchagua.";
            $this->reply($tenant, $phone, implode("\n", $lines));
            return;
        }
    }

    private function startStaffMenu(Tenant $tenant, string $phone, WhatsappRenewalSession $session, User $staff): void
    {
        $session->update(['flow' => 'staff_menu', 'state' => ['staff_id' => $staff->id]]);
        $this->reply($tenant, $phone, "Habari {$staff->name}! Chagua:\n"
            . "1) Followups Zangu (Leo/Zilizochelewa)\n"
            . "2) Tafuta Mteja Kumsaidia\n\n"
            . 'Jibu na namba. MENU = ondoka.');
    }

    /** The staff member's own active follow-ups due today or overdue — from the existing web-portal Followup system. */
    private function sendStaffFollowups(Tenant $tenant, string $phone, User $staff): void
    {
        $followups = \App\Models\Followup::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->where('user_id', $staff->id)
            ->whereIn('status', ['pending', 'open', 'broken'])
            ->whereDate('next_followup', '<=', now()->toDateString())
            ->whereHas('document', fn ($q) => $q->where('status', '!=', 'cancelled'))
            ->with(['client', 'document'])
            ->orderBy('next_followup')
            ->limit(15)
            ->get();

        if ($followups->isEmpty()) {
            $this->reply($tenant, $phone, 'Huna followups zilizopangiwa leo au zilizochelewa. 👍');
            return;
        }

        $lines = ['*Followups Zako (' . $followups->count() . ')*'];
        foreach ($followups as $f) {
            $overdue = $f->next_followup && $f->next_followup->isPast() ? ' ⚠️ IMECHELEWA' : '';
            $lines[] = "\n• {$f->client?->name}" . $overdue
                . "\n  Invoice {$f->document?->document_number} — TZS " . number_format((float) ($f->document?->balance_due ?? 0))
                . "\n  Tarehe: " . ($f->next_followup?->format('d M Y') ?? '—');
        }

        $this->reply($tenant, $phone, implode("\n", $lines));
    }

    private function startStaffClientSearch(Tenant $tenant, string $phone, WhatsappRenewalSession $session, User $staff): void
    {
        $session->update(['flow' => 'staff_search', 'state' => ['step' => 'search', 'staff_id' => $staff->id]]);
        $this->reply($tenant, $phone, 'Andika jina, email, au namba ya simu ya mteja unayemsaidia.');
    }

    /** @return \Illuminate\Support\Collection<int, Client> */
    private function searchClientsForStaff(Tenant $tenant, string $query): \Illuminate\Support\Collection
    {
        $base = Client::withoutGlobalScopes()->whereNull('deleted_at')->where('tenant_id', $tenant->id);

        if (preg_match('/^\+?\d[\d\s-]{6,}$/', $query)) {
            return PhoneHelper::wherePhone((clone $base), 'phone', $query)->limit(10)->get();
        }

        return $base->where(fn ($q) => $q
            ->where('name', 'like', "%{$query}%")
            ->orWhere('email', 'like', "%{$query}%"))
            ->limit(10)->get();
    }

    private function confirmStaffAssist(Tenant $tenant, string $phone, WhatsappRenewalSession $session, User $staff, Client $client): void
    {
        Log::info('WhatsApp staff-assist session started', [
            'tenant_id' => $tenant->id, 'staff_id' => $staff->id, 'staff_name' => $staff->name,
            'client_id' => $client->id, 'client_name' => $client->name,
        ]);

        $lang = 'sw';
        $session->update([
            'client_id' => $client->id, 'assisted_by_user_id' => $staff->id,
            'flow' => null, 'state' => null, 'language' => $lang, 'items' => null,
            'confirmed_at' => now(), 'expires_at' => now()->addHours(2),
        ]);

        $this->reply($tenant, $phone, "👤 Umeunganishwa na *{$client->name}*. Unamsaidia sasa.");
        $this->sendRootMenu($tenant, $client, $phone, $lang);
    }

    // ── Language ─────────────────────────────────────────────────────────

    private function startLanguageSelect(Tenant $tenant, string $phone, ?Client $clientMatch): void
    {
        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            [
                'client_id' => $clientMatch?->id,
                'flow' => 'language_select',
                'state' => ['next' => $clientMatch ? 'surname' : 'register'],
                'items' => null,
                'language' => null,
                'confirmed_at' => null,
                'attempts' => 0,
                'expires_at' => now()->addMinutes(10),
            ],
        );

        $this->reply($tenant, $phone,
            'Karibu MoBilling! Please select your preferred language to continue. Tafadhali chagua lugha: 1) English  2) Kiswahili');
    }

    private function handleLanguageStep(Tenant $tenant, string $phone, WhatsappRenewalSession $session, string $text): void
    {
        $lang = match (true) {
            (bool) preg_match('/^\s*1\s*$/', $text) => 'en',
            (bool) preg_match('/^\s*2\s*$/', $text) => 'sw',
            (bool) preg_match('/english/i', $text) => 'en',
            (bool) preg_match('/swahili|kiswahili/i', $text) => 'sw',
            default => null,
        };

        if (!$lang) {
            $this->reply($tenant, $phone, 'Please reply 1 for English or 2 for Kiswahili. Tafadhali jibu 1 kwa English au 2 kwa Kiswahili.');
            return;
        }

        // Ask explicitly rather than silently deciding from the phone match alone —
        // the match is still used as a cross-check once they answer (see
        // handleSurnameStep's 'has_account'/'want_account' steps), never as the
        // sole decider, so someone can always say "no account" honestly and be
        // routed correctly either way.
        $session->update(['language' => $lang, 'flow' => null, 'state' => ['step' => 'has_account']]);
        $this->reply($tenant, $phone, $this->t($lang,
            'Je, una akaunti ya MoBilling? Jibu 1) Ndiyo 2) Hapana',
            'Do you have a MoBilling account? Reply 1) Yes 2) No'
        ));
    }

    // ── Identity ─────────────────────────────────────────────────────────

    private function startRegistration(Tenant $tenant, string $phone, string $lang): void
    {
        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => null, 'flow' => 'register', 'language' => $lang, 'state' => ['step' => 'ask_name'], 'items' => null, 'confirmed_at' => null, 'attempts' => 0, 'expires_at' => now()->addMinutes(10)],
        );

        $this->reply($tenant, $phone, $this->t($lang,
            'Bado hujasajiliwa. Tafadhali andika jina lako kamili (jina la kwanza na la ukoo) kujisajili.',
            "You're not registered with us yet. Please reply with your full name (first and last) to register."
        ));
    }

    private function handleRegistrationStep(Tenant $tenant, string $phone, WhatsappRenewalSession $session, string $text): void
    {
        $lang = $session->language ?? 'sw';
        $name = trim(preg_replace('/\s+/', ' ', $text));

        if (mb_strlen($name) < 3 || !str_contains($name, ' ')) {
            $this->reply($tenant, $phone, $this->t($lang,
                'Tafadhali andika jina lako kamili (jina la kwanza na la ukoo), mfano: Juma Pesa.',
                'Please reply with your full name (first and last), e.g. Juma Pesa.'
            ));
            return;
        }

        [$firstName, $lastName] = array_pad(explode(' ', $name, 2), 2, null);

        $client = Client::withoutGlobalScopes()->create([
            'tenant_id' => $tenant->id,
            'name' => $name,
            'first_name' => $firstName,
            'last_name' => $lastName,
            'phone' => '0' . $phone,
            'status' => 'active',
        ]);

        $session->update(['client_id' => $client->id, 'flow' => null, 'state' => null, 'confirmed_at' => now(), 'items' => null, 'expires_at' => now()->addMinutes(10)]);

        $this->reply($tenant, $phone, $this->t($lang, "Asante {$name}! Umesajiliwa MoBilling.", "Thank you, {$name}! You're now registered with MoBilling."));
        $this->sendRootMenu($tenant, $client, $phone, $lang);
    }

    /**
     * Two verification factors, not one — a client who genuinely forgot their
     * surname (or mistyped it twice) still has a path back into their own
     * account via their registered email, rather than a dead end. This is
     * deliberately never a route to *registering a new* account when a phone
     * already matches an existing client — only ever re-proving the same one,
     * so a failed verification can never create a duplicate.
     */
    private function handleSurnameStep(Tenant $tenant, string $phone, WhatsappRenewalSession $session, string $text): void
    {
        $lang = $session->language ?? 'sw';
        $client = Client::withoutGlobalScopes()->whereNull('deleted_at')->find($session->client_id);
        $state = $session->state ?? [];

        if (($state['step'] ?? 'surname') === 'has_account') {
            if (preg_match('/^\s*1\s*$/', $text) || preg_match('/^\s*(ndiyo|yes)\s*$/i', $text)) {
                if ($client) {
                    $session->update(['state' => ['step' => 'surname']]);
                    $this->reply($tenant, $phone, $this->t($lang,
                        'Karibu MoBilling! Kwa uthibitisho, tafadhali jibu kwa jina lako la ukoo (surname) lililosajiliwa.',
                        'Welcome to MoBilling! For verification, please reply with the surname registered with your account.'
                    ));
                    return;
                }

                $session->update(['state' => ['step' => 'want_account']]);
                $this->reply($tenant, $phone, $this->t($lang,
                    'Samahani, hatujaweza kupata akaunti yenye namba hii ya simu. Je, ungependa tukutengenezee akaunti mpya ya MoBilling? Jibu 1) Ndiyo 2) Hapana',
                    "Sorry, we couldn't find an account with this phone number. Would you like us to create a new MoBilling account for you? Reply 1) Yes 2) No"
                ));
                return;
            }

            $session->update(['state' => ['step' => 'want_account']]);
            $this->reply($tenant, $phone, $this->t($lang,
                'Je, ungependa tukutengenezee akaunti ya MoBilling? Jibu 1) Ndiyo 2) Hapana',
                'Would you like us to create a MoBilling account for you? Reply 1) Yes 2) No'
            ));
            return;
        }

        if (($state['step'] ?? '') === 'want_account') {
            if (!preg_match('/^\s*1\s*$/', $text) && !preg_match('/^\s*(ndiyo|yes)\s*$/i', $text)) {
                $session->delete();
                $this->reply($tenant, $phone, $this->t($lang,
                    'Sawa, tukihitaji tutakujulisha. Asante!',
                    "Okay, we'll reach out if we need to. Thanks!"
                ));
                return;
            }

            // Re-check by phone right before creating anything — closes the loop
            // even if they mistakenly said "no account" earlier despite having one.
            $existing = Client::withoutGlobalScopes()->whereNull('deleted_at')->where('tenant_id', $tenant->id);
            $existing = PhoneHelper::wherePhone($existing, 'phone', $phone)->first();

            if ($existing) {
                $session->update(['client_id' => $existing->id, 'state' => ['step' => 'surname']]);
                $this->reply($tenant, $phone, $this->t($lang,
                    'Kumbe una akaunti tayari! Tuthibitishe — jibu kwa jina lako la ukoo (surname) lililosajiliwa.',
                    "Turns out you already have an account! Let's verify it — please reply with your registered surname."
                ));
                return;
            }

            $this->startRegistration($tenant, $phone, $lang);
            return;
        }

        if (($state['step'] ?? 'surname') === 'email') {
            if ($client && $client->email && mb_strtolower(trim($text)) === mb_strtolower(trim($client->email))) {
                $session->update(['confirmed_at' => now()]);
                $this->sendRootMenu($tenant, $client, $phone, $lang);
                return;
            }

            $session->delete();
            $this->reply($tenant, $phone, $this->t($lang,
                'Samahani, hatujaweza kuthibitisha akaunti yako. Tafadhali wasiliana nasi kwa msaada.',
                "Sorry, we still couldn't verify your account. Please contact us for help."
            ));
            return;
        }

        if ($client && $this->surnameMatches($client, $text)) {
            $session->update(['confirmed_at' => now()]);
            $this->sendRootMenu($tenant, $client, $phone, $lang);
            return;
        }

        if ($session->attempts >= 1) {
            if (!$client || !$client->email) {
                $session->delete();
                $this->reply($tenant, $phone, $this->t($lang,
                    'Samahani, hatujaweza kuthibitisha jina lako. Tafadhali wasiliana nasi kwa msaada.',
                    "Sorry, we couldn't verify your name. Please contact us for help."
                ));
                return;
            }

            $session->update(['state' => ['step' => 'email']]);
            $this->reply($tenant, $phone, $this->t($lang,
                'Samahani, jina halikubaliki. Jaribu kwa njia nyingine — andika barua pepe yako iliyosajiliwa MoBilling.',
                "Sorry, that still doesn't match. Let's try another way — please reply with the email address registered with your MoBilling account."
            ));
            return;
        }

        $session->increment('attempts');
        $this->reply($tenant, $phone, $this->t($lang,
            'Samahani, jina hilo halifanani na tulilonalo. Tafadhali jaribu tena — jina la ukoo (surname) lililosajiliwa MoBilling.',
            "Sorry, that doesn't match what we have. Please try again — the surname registered with MoBilling."
        ));
    }

    /** Loosely matches typed text against the client's last name, or any word in their full name. */
    private function surnameMatches(Client $client, string $text): bool
    {
        $typed = mb_strtolower(trim($text));
        if ($typed === '') {
            return false;
        }

        if ($client->last_name && mb_strtolower(trim($client->last_name)) === $typed) {
            return true;
        }

        $words = preg_split('/\s+/', mb_strtolower(trim((string) $client->name)));

        return in_array($typed, $words, true);
    }

    /** @return array{0: ?Tenant, 1: ?MosmsAccount} */
    private function authenticate(Request $request): array
    {
        if (!hash_equals((string) config('services.mosms.inbound_webhook_secret'), (string) $request->secret)) {
            return [null, null];
        }

        $account = MosmsAccount::withoutGlobalScopes()
            ->where('mosms_tenant_id', $request->mosms_tenant_id)
            ->first();

        if (!$account) {
            Log::warning('WhatsApp webhook: no MosmsAccount for mosms_tenant_id', ['mosms_tenant_id' => $request->mosms_tenant_id]);
            return [null, null];
        }

        $tenant = Tenant::withoutGlobalScopes()->find($account->tenant_id);

        return [$tenant, $account];
    }

    /** sw/en text picker — the one place every bilingual message goes through. */
    private function t(string $lang, string $sw, string $en): string
    {
        return $lang === 'en' ? $en : $sw;
    }

    // ── Root menu ────────────────────────────────────────────────────────

    /**
     * Once verified, a client stays recognised on this phone for 30 days
     * (reset on every reply while idle at the root menu) — surname
     * verification (and language choice) only happen once, not on every
     * message, until they explicitly log out (option 0) or 30 days of
     * inactivity pass.
     */
    private function sendRootMenu(Tenant $tenant, Client $client, string $phone, string $lang): void
    {
        // Staff-assist sessions carry a short TTL and an on-screen banner instead of the
        // normal 30-day "stay logged in" window — this is a staff member temporarily acting
        // on a client's behalf, not the client's own persistent login.
        $existing = WhatsappRenewalSession::withoutGlobalScopes()->where('tenant_id', $tenant->id)->where('phone', $phone)->first();
        $assistedBy = $existing?->assisted_by_user_id;

        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'assisted_by_user_id' => $assistedBy, 'flow' => null, 'state' => null, 'items' => null, 'language' => $lang, 'confirmed_at' => now(), 'expires_at' => $assistedBy ? now()->addHours(2) : now()->addDays(30)],
        );

        $banner = '';
        if ($assistedBy) {
            $staff = User::withoutGlobalScopes()->find($assistedBy);
            $banner = $this->t($lang, "👤 Unamsaidia {$client->name} (staff: " . ($staff?->name ?? '?') . ")\n\n", "👤 Assisting {$client->name} (staff: " . ($staff?->name ?? '?') . ")\n\n");
        }

        $this->reply($tenant, $phone, $banner . $this->t($lang,
            "Habari {$client->name}! Chagua huduma: "
                . '1) Domain Registration · 2) Domain Renewal · 3) Website Hosting · '
                . '4) Business Email Hosting · 5) Angalia na Lipa Invoice · '
                . '6) WHOIS ya Domain · 7) Angalia kama Domain Inapatikana · '
                . '8) Badilisha Nameservers (DNS) · 9) Taarifa za Akaunti · '
                . "0) Toka (Logout). Jibu na namba.\n\n"
                . 'Andika MOSMS kwa huduma za akaunti yako ya SMS/WhatsApp bulk.',
            "Hi {$client->name}! Choose a service: "
                . '1) Domain Registration · 2) Domain Renewal · 3) Website Hosting · '
                . '4) Business Email Hosting · 5) View and Pay Invoices · '
                . '6) Domain WHOIS · 7) Check Domain Availability · '
                . '8) Change Nameservers (DNS) · 9) Account Information · '
                . "0) Logout. Reply with a number.\n\n"
                . 'Reply MOSMS for your bulk SMS/WhatsApp account.'
        ));
    }

    /** Full account snapshot: contact details, active domains, active subscriptions, outstanding balance. */
    private function sendAccountInfo(Tenant $tenant, Client $client, string $phone, string $lang): void
    {
        $domains = Domain::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)->where('client_id', $client->id)
            ->whereNotIn('status', ['cancelled', 'transferred_out'])
            ->orderBy('expires_at')
            ->get();

        $subscriptions = \App\Models\ClientSubscription::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)->where('client_id', $client->id)
            ->whereIn('status', ['active', 'pending', 'suspended'])
            // Unauthenticated webhook context — the relation must also bypass
            // ProductService's own tenant scope, or it silently resolves to null.
            ->with(['productService' => fn ($q) => $q->withoutGlobalScopes()])
            ->orderBy('expire_date')
            ->get();

        // balance_due is a computed accessor (total - paid_amount), not a DB column — sum in PHP.
        $balanceDue = Document::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)->where('client_id', $client->id)
            ->where('type', 'invoice')->whereNotIn('status', ['draft', 'cancelled'])
            ->get()
            ->sum(fn ($d) => max($d->balance_due, 0));

        $sw = $lang === 'sw';
        $lines = [$sw ? '*Taarifa za Akaunti*' : '*Account Information*'];
        $lines[] = ($sw ? '• Jina: ' : '• Name: ') . $client->name;
        $lines[] = '• Email: ' . ($client->email ?: '—');
        $lines[] = ($sw ? '• Simu: ' : '• Phone: ') . ($client->phone ?: '—');
        $lines[] = ($sw ? '• Kampuni: ' : '• Company: ') . $tenant->name;

        if ($domains->isNotEmpty()) {
            $lines[] = "\n" . ($sw ? '*Domain (' : '*Domains (') . $domains->count() . '):*';
            foreach ($domains as $d) {
                $exp = $d->expires_at ? $d->expires_at->format('d M Y') : '—';
                $lines[] = "• {$d->name} — {$d->status}, " . ($sw ? "inaisha {$exp}" : "expires {$exp}");
            }
        }

        if ($subscriptions->isNotEmpty()) {
            $lines[] = "\n" . ($sw ? '*Huduma (' : '*Services (') . $subscriptions->count() . '):*';
            foreach ($subscriptions as $s) {
                $exp = $s->expire_date ? $s->expire_date->format('d M Y') : '—';
                $name = $s->productService?->name ?? ($sw ? 'Huduma' : 'Service');
                $lines[] = "• {$name}" . ($s->label ? " — {$s->label}" : '') . " — {$s->status}, " . ($sw ? "inaisha {$exp}" : "expires {$exp}");
            }
        }

        $lines[] = "\n" . ($sw ? '*Deni linalodaiwa:* TZS ' : '*Outstanding balance:* TZS ') . number_format($balanceDue);

        $this->reply($tenant, $phone, implode("\n", $lines));
    }

    private function logout(Tenant $tenant, string $phone, string $lang): void
    {
        WhatsappRenewalSession::where('tenant_id', $tenant->id)->where('phone', $phone)->delete();
        $this->reply($tenant, $phone, $this->t($lang,
            'Umetoka kwenye akaunti yako. Tuma ujumbe wowote kuingia tena.',
            "You've been logged out. Send any message to sign in again."
        ));
    }

    /**
     * Ends a flow's final step by delivering its message and, right after,
     * the root menu again — without this a client who just finished a WHOIS
     * lookup or an order had no visible way back to the menu except
     * re-verifying their surname from scratch (reported live).
     */
    private function finishFlow(Tenant $tenant, Client $client, string $phone, string $message, string $lang): void
    {
        $this->reply($tenant, $phone, $message);
        $this->sendRootMenu($tenant, $client, $phone, $lang);
    }

    private function handleRootStep(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, string $text, RenewalBundleService $bundler, string $lang): void
    {
        // Renewal picker already active (items populated by sendMenu()): a digit picks one.
        if (!empty($session->items) && preg_match('/^\s*([1-9])\s*$/', $text, $m)) {
            $this->pickAndGenerate($tenant, $client, $phone, $session, (int) $m[1], $bundler, $lang);
            return;
        }

        match (true) {
            (bool) preg_match('/^\s*0\s*$/', $text) => $this->logout($tenant, $phone, $lang),
            (bool) preg_match('/^\s*1\s*$/', $text) => $this->startOrderDomain($tenant, $client, $phone, $lang),
            (bool) preg_match('/^\s*2\s*$/', $text) => $this->sendMenu($tenant, $client, $phone, $bundler, $lang),
            (bool) preg_match('/^\s*3\s*$/', $text) => $this->startHostingSubmenu($tenant, $client, $phone, $lang),
            (bool) preg_match('/^\s*4\s*$/', $text) => $this->startOrderHosting($tenant, $client, $phone, 'Business E-mail', $lang),
            (bool) preg_match('/^\s*5\s*$/', $text) => $this->startPayInvoice($tenant, $client, $phone, $lang),
            (bool) preg_match('/^\s*6\s*$/', $text) => $this->startWhois($tenant, $client, $phone, $lang),
            (bool) preg_match('/^\s*7\s*$/', $text) => $this->startCheckAvailability($tenant, $client, $phone, $lang),
            (bool) preg_match('/^\s*8\s*$/', $text) => $this->startChangeDns($tenant, $client, $phone, $lang),
            (bool) preg_match('/^\s*9\s*$/', $text) => (function () use ($tenant, $client, $phone, $lang) {
                $this->sendAccountInfo($tenant, $client, $phone, $lang);
                $this->sendRootMenu($tenant, $client, $phone, $lang);
            })(),
            default => $this->sendRootMenu($tenant, $client, $phone, $lang),
        };
    }

    // ── Website Hosting submenu + "Hosting Yangu" self-service ──────────
    // Everything here reads LOCAL data only (hosting_accounts as last synced by
    // hosting:reconcile) — the webhook never calls WHM live, except the one
    // explicit, client-requested cPanel SSO link (HostingSsoService).

    private function startHostingSubmenu(Tenant $tenant, Client $client, string $phone, string $lang): void
    {
        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'flow' => 'hosting_submenu', 'state' => ['step' => 'choose'], 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(10)],
        );

        $this->reply($tenant, $phone, $this->t($lang,
            '*Website Hosting* — Chagua: 1) Agiza hosting mpya · 2) Hosting yangu (hali, cPanel, malipo). Jibu na namba, au andika MENU kurudi.',
            '*Website Hosting* — Choose: 1) Order new hosting · 2) My hosting (status, cPanel, payment). Reply with a number, or type MENU to go back.'
        ));
    }

    private function handleHostingSubmenuStep(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, string $text, string $lang): void
    {
        if (preg_match('/^\s*1\s*$/', $text)) {
            $this->startOrderHosting($tenant, $client, $phone, 'Web Hosting', $lang);
        } elseif (preg_match('/^\s*2\s*$/', $text)) {
            $this->startHostingManage($tenant, $client, $phone, $lang);
        } else {
            $this->reply($tenant, $phone, $this->t($lang, 'Samahani, jibu 1 au 2 (au MENU kurudi).', 'Sorry, reply 1 or 2 (or MENU to go back).'));
        }
    }

    /** The client's own hosting accounts — tenant + client scoped, soft-deleted subscriptions excluded. */
    private function clientHostingAccounts(Tenant $tenant, Client $client)
    {
        return HostingAccount::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->whereNotIn('status', ['terminated'])
            ->whereHas('subscription', fn ($q) => $q->withoutGlobalScopes()
                ->where('tenant_id', $tenant->id)
                ->where('client_id', $client->id)
                ->whereNull('deleted_at'))
            ->with(['subscription' => fn ($q) => $q->withoutGlobalScopes()])
            ->orderBy('domain');
    }

    private function startHostingManage(Tenant $tenant, Client $client, string $phone, string $lang): void
    {
        $accounts = $this->clientHostingAccounts($tenant, $client)->limit(9)->get();

        if ($accounts->isEmpty()) {
            $this->finishFlow($tenant, $client, $phone, $this->t($lang,
                'Huna hosting yoyote iliyosajiliwa kwetu kwa sasa. Chagua 3 kisha 1 kuagiza hosting mpya.',
                "You don't have any hosting registered with us yet. Choose 3 then 1 to order new hosting."
            ), $lang);
            return;
        }

        if ($accounts->count() === 1) {
            $this->showHostingAccount($tenant, $client, $phone, $accounts->first(), $lang, multiple: false);
            return;
        }

        $lines = [];
        foreach ($accounts as $i => $a) {
            $lines[] = ($i + 1) . ". {$a->domain} — " . $this->hostingStatusLabel($a->status, $lang);
        }

        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'flow' => 'hosting_manage', 'state' => ['step' => 'pick_account', 'account_ids' => $accounts->pluck('id')->all()], 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(10)],
        );

        $this->reply($tenant, $phone, $this->t($lang,
            '*Hosting yako* — chagua akaunti: ' . implode(' · ', $lines) . '. Jibu na namba.',
            '*Your hosting* — choose an account: ' . implode(' · ', $lines) . '. Reply with a number.'
        ));
    }

    private function hostingStatusLabel(string $status, string $lang): string
    {
        return match ($status) {
            'active' => $this->t($lang, 'inafanya kazi', 'active'),
            'suspended' => $this->t($lang, 'imesimamishwa', 'suspended'),
            'failed' => $this->t($lang, 'imeshindwa kuwashwa', 'failed'),
            'pending' => $this->t($lang, 'inaandaliwa', 'pending'),
            default => $status,
        };
    }

    private function handleHostingManageStep(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, string $text, string $lang): void
    {
        $state = $session->state ?? [];
        $step = $state['step'] ?? 'pick_account';

        if (in_array($step, ['email_menu', 'upgrade_pick', 'upgrade_confirm', 'ask_email_name', 'ask_ticket_text'], true)) {
            $this->handleHostingSubStep($tenant, $client, $phone, $session, $text, $lang, $step, $state);
            return;
        }

        if (!preg_match('/^\s*([1-9])\s*$/', $text, $m)) {
            $this->reply($tenant, $phone, $this->t($lang, 'Samahani, jibu na namba sahihi kutoka kwenye orodha (au MENU kurudi).', 'Sorry, reply with a valid number from the list (or MENU to go back).'));
            return;
        }
        $n = (int) $m[1];

        if ($step === 'pick_account') {
            $id = $state['account_ids'][$n - 1] ?? null;
            $account = $id ? $this->clientHostingAccounts($tenant, $client)->where('hosting_accounts.id', $id)->first() : null;
            if (!$account) {
                $this->reply($tenant, $phone, $this->t($lang, 'Samahani, chagua namba sahihi kutoka kwenye orodha.', 'Sorry, please choose a valid number from the list.'));
                return;
            }
            $this->showHostingAccount($tenant, $client, $phone, $account, $lang, multiple: count($state['account_ids']) > 1);
            return;
        }

        // account_menu: options were computed when the menu was shown.
        $option = $state['options'][$n - 1] ?? null;
        $account = !empty($state['account_id'])
            ? $this->clientHostingAccounts($tenant, $client)->where('hosting_accounts.id', $state['account_id'])->first()
            : null;
        if (!$option || !$account) {
            $this->reply($tenant, $phone, $this->t($lang, 'Samahani, chagua namba sahihi kutoka kwenye orodha.', 'Sorry, please choose a valid number from the list.'));
            return;
        }

        if ($option === 'back') {
            $this->startHostingManage($tenant, $client, $phone, $lang);
        } elseif ($option === 'cpanel') {
            $this->sendCpanelLink($tenant, $client, $phone, $session, $account, $lang);
        } elseif ($option === 'support') {
            $this->askHostingSupportText($tenant, $client, $phone, $session, $account, $lang);
        } elseif ($option === 'upgrade') {
            $this->showUpgradeOptions($tenant, $client, $phone, $session, $account, $lang);
        } elseif ($option === 'email') {
            $this->showEmailMenu($tenant, $client, $phone, $session, $account, $lang);
        } elseif ($option === 'connect') {
            $this->showConnectDomain($tenant, $client, $phone, $session, $account, $lang);
        } elseif (str_starts_with($option, 'invoice:')) {
            $doc = $this->unpaidHostingInvoices($tenant, $client, $account)->firstWhere('id', substr($option, 8));
            if (!$doc) {
                $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, invoice hiyo haipatikani tena.', 'Sorry, that invoice is no longer available.'), $lang);
                return;
            }
            // The existing pay flow (Pesapal / bank details). Paying it fires
            // SubscriptionActivationService -> ClientSubscriptionObserver ->
            // ReactivateHostingAccount, which is what restores a suspended account.
            $this->offerPayment($tenant, $client, $phone, $doc, $lang);
        }
    }

    /** Unpaid invoices tied to this account's subscription via RecurringInvoiceLog. balance_due is an accessor, so filter in PHP. */
    private function unpaidHostingInvoices(Tenant $tenant, Client $client, HostingAccount $account): \Illuminate\Support\Collection
    {
        $docIds = \App\Models\RecurringInvoiceLog::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->where('client_id', $client->id)
            ->where('client_subscription_id', $account->client_subscription_id)
            ->whereNotNull('document_id')
            ->pluck('document_id');

        if ($docIds->isEmpty()) {
            return collect();
        }

        return Document::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->where('client_id', $client->id)
            ->where('type', 'invoice')
            ->whereIn('id', $docIds)
            ->whereIn('status', ['sent', 'overdue', 'partial'])
            ->orderBy('due_date')
            ->get()
            ->filter(fn ($d) => $d->balance_due > 0)
            ->values()
            ->take(6);
    }

    /** "2186M" -> 2186.0 ; anything else -> null (we then show the raw stored text, never a guessed number). */
    private function parseMegabytes(mixed $raw): ?float
    {
        if (is_string($raw) && preg_match('/^(\d+(?:\.\d+)?)\s*M$/i', trim($raw), $m)) {
            return (float) $m[1];
        }
        return null;
    }

    private function showHostingAccount(Tenant $tenant, Client $client, string $phone, HostingAccount $account, string $lang, bool $multiple): void
    {
        $sw = $lang === 'sw';
        $meta = $account->meta ?? [];
        $sub = $account->subscription;

        $meaning = match ($account->status) {
            'active' => $this->t($lang, 'Website yako iko hewani na inafanya kazi.', 'Your hosting is live and working.'),
            'suspended' => $this->t($lang, 'Hosting imesimamishwa, website haipatikani hadi itakaporejeshwa.', 'Your hosting is suspended, so the website is offline until it is restored.'),
            'failed' => $this->t($lang, 'Kuna tatizo la kiufundi na akaunti hii; tunalishughulikia.', 'There is a technical problem with this account; we are looking into it.'),
            'pending' => $this->t($lang, 'Akaunti bado inaandaliwa.', 'The account is still being set up.'),
            default => '',
        };

        $lines = ["*Hosting: {$account->domain}*"];
        $lines[] = ($sw ? '• Hali: ' : '• Status: ') . $this->hostingStatusLabel($account->status, $lang) . ($meaning ? " — {$meaning}" : '');
        if ($account->package || !empty($meta['plan'])) {
            $lines[] = ($sw ? '• Kifurushi: ' : '• Package: ') . ($account->package ?: $meta['plan']);
        }
        $lines[] = ($sw ? '• Domain: ' : '• Domain: ') . $account->domain;

        $domain = Domain::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)->where('client_id', $client->id)
            ->where('name', $account->domain)->first();

        if ($sub?->expire_date) {
            $lines[] = ($sw ? '• Hosting inaisha: ' : '• Hosting expires: ') . $sub->expire_date->format('d M Y');
        }
        if ($domain?->expires_at) {
            $lines[] = ($sw ? '• Domain inaisha: ' : '• Domain expires: ') . $domain->expires_at->format('d M Y');
        }

        // Disk: only what hosting:reconcile really stored.
        $usedRaw = $meta['disk_used'] ?? null;
        $limitRaw = $meta['disk_limit'] ?? null;
        if ($usedRaw !== null && $usedRaw !== '') {
            $used = $this->parseMegabytes($usedRaw);
            $limit = $this->parseMegabytes($limitRaw);
            if ($used !== null && $limit !== null && $limit > 0) {
                $pct = (int) round($used / $limit * 100);
                $filled = max(0, min(10, (int) round(min($pct, 100) / 10)));
                $bar = str_repeat('█', $filled) . str_repeat('░', 10 - $filled);
                $lines[] = ($sw ? '• Nafasi (disk): ' : '• Disk: ') . "{$usedRaw} / {$limitRaw} {$bar} {$pct}%";
            } else {
                $lines[] = ($sw ? '• Nafasi (disk): ' : '• Disk: ') . $usedRaw . ($limitRaw ? " / {$limitRaw}" : '');
            }
        }

        // SSL: only when that domain's SSL check has actually stored a result.
        if ($domain && is_array($domain->meta) && array_key_exists('ssl_valid', $domain->meta)) {
            $sslExp = !empty($domain->meta['ssl_expires_at']) ? \Illuminate\Support\Carbon::parse($domain->meta['ssl_expires_at'])->format('d M Y') : null;
            $lines[] = ($sw ? '• SSL: ' : '• SSL: ')
                . ($domain->meta['ssl_valid'] ? ($sw ? 'halali' : 'valid') : ($sw ? 'si halali / tatizo' : 'not valid / problem'))
                . ($sslExp ? ($sw ? ", inaisha {$sslExp}" : ", expires {$sslExp}") : '');
        }

        $lines[] = $account->last_synced_at
            ? ($sw ? '• Imesasishwa mara ya mwisho: ' : '• Last synced: ') . $account->last_synced_at->format('d M Y H:i')
            : ($sw ? '• Bado haijasasishwa (taarifa za matumizi hazipo).' : '• Not synced yet (no usage data).');

        // Options
        $options = [];
        $optLines = [];
        $add = function (string $key, string $label) use (&$options, &$optLines) {
            $options[] = $key;
            $optLines[] = count($options) . ") {$label}";
        };

        if ($account->status === 'active') {
            $add('cpanel', $this->t($lang, 'Fungua cPanel', 'Open cPanel'));
            $add('upgrade', $this->t($lang, 'Boresha kifurushi', 'Upgrade package'));
            $add('email', $this->t($lang, 'Email zangu', 'My email accounts'));
            $add('connect', $this->t($lang, 'Unganisha domain na hosting', 'Connect domain to hosting'));
        } elseif ($account->status === 'suspended') {
            $invoices = $this->unpaidHostingInvoices($tenant, $client, $account);
            if ($invoices->isNotEmpty()) {
                $lines[] = $sw
                    ? '• Ili kurejesha, lipia invoice hapa chini; hosting itawashwa baada ya malipo kupokelewa.'
                    : '• To restore it, pay an invoice below; hosting is switched back on once payment is received.';
                foreach ($invoices as $inv) {
                    $add('invoice:' . $inv->id, $this->t($lang,
                        "Lipa {$inv->document_number} — TZS " . number_format((float) $inv->balance_due),
                        "Pay {$inv->document_number} — TZS " . number_format((float) $inv->balance_due)));
                }
            } else {
                $lines[] = $sw
                    ? '• Hatuna deni linalojulikana kwa hosting hii; tafadhali wasiliana nasi ili tuchunguze.'
                    : "• We don't see any known unpaid invoice for this hosting; please contact us so we can look into it.";
            }
        }
        $add('support', $this->t($lang, 'Wasiliana na msaada', 'Contact support'));
        if ($multiple) {
            $add('back', $this->t($lang, 'Hosting nyingine', 'Another hosting account'));
        }

        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'flow' => 'hosting_manage', 'state' => ['step' => 'account_menu', 'account_id' => $account->id, 'options' => $options, 'account_ids' => [$account->id]], 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(10)],
        );

        $msg = implode("\n", $lines);
        if ($optLines) {
            $msg .= "\n\n" . ($sw ? 'Chagua: ' : 'Choose: ') . implode(' · ', $optLines) . ($sw ? '. Jibu na namba, au MENU kurudi.' : '. Reply with a number, or MENU to go back.');
        } else {
            $msg .= "\n\n" . ($sw ? 'Andika MENU kurudi.' : 'Type MENU to go back.');
        }
        $this->reply($tenant, $phone, $msg);
    }

    private function sendCpanelLink(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, HostingAccount $account, string $lang): void
    {
        // A staff member is on THEIR phone here; a cPanel login link would hand full control of the
        // client's hosting to whoever holds that phone. Staff use the admin panel instead.
        if ($session->assisted_by_user_id) {
            $this->reply($tenant, $phone, $this->t($lang,
                'Kwa usalama, kiungo cha cPanel hakitumwi kwenye hali ya staff. Tafadhali tumia admin panel kufungua cPanel ya mteja.',
                'For security the cPanel link is not sent in staff-assist mode. Please use the admin panel to open the client\'s cPanel.'
            ));
            return;
        }

        if ($account->status !== 'active') {
            $this->reply($tenant, $phone, $this->t($lang, 'cPanel inapatikana tu kwa hosting inayofanya kazi.', 'cPanel is only available for an active hosting account.'));
            return;
        }

        try {
            $url = app(\App\Services\Hosting\HostingSsoService::class)->cpanelUrl($account);
        } catch (\Throwable $e) {
            // Never log the exception message here: it can carry WHM request details.
            Log::warning('WhatsApp cPanel SSO failed', ['client_id' => $client->id, 'hosting_account_id' => $account->id]);
            $this->reply($tenant, $phone, $this->t($lang,
                'Samahani, hatuwezi kufungua cPanel kwa sasa. Tafadhali jaribu tena baadaye au wasiliana nasi.',
                "Sorry, we can't open cPanel right now. Please try again later or contact us."
            ));
            return;
        }

        Log::info('WhatsApp cPanel SSO link issued', ['client_id' => $client->id, 'hosting_account_id' => $account->id]);

        $this->replyWithCtaUrl(
            $tenant, $phone,
            $this->t($lang,
                "Bonyeza kitufe hapa chini kufungua cPanel ya {$account->domain}. Kiungo ni cha mara moja na kinaisha muda haraka; usimtumie mtu mwingine.",
                "Tap the button below to open cPanel for {$account->domain}. The link works once and expires quickly; don't share it."
            ),
            $this->t($lang, 'Fungua cPanel', 'Open cPanel'),
            $url
        );
    }

    private function hostingAccountFromState(Tenant $tenant, Client $client, array $state): ?HostingAccount
    {
        return !empty($state['account_id'])
            ? $this->clientHostingAccounts($tenant, $client)->where('hosting_accounts.id', $state['account_id'])->first()
            : null;
    }

    private function setHostingState(Tenant $tenant, Client $client, string $phone, array $state): void
    {
        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'flow' => 'hosting_manage', 'state' => $state, 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(10)],
        );
    }

    /** Steps of hosting_manage that are not the plain numbered account menu. */
    private function handleHostingSubStep(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, string $text, string $lang, string $step, array $state): void
    {
        $account = $this->hostingAccountFromState($tenant, $client, $state);
        if (!$account) {
            $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, akaunti hiyo haipatikani tena.', 'Sorry, that account is no longer available.'), $lang);
            return;
        }

        if ($step === 'ask_ticket_text') {
            $this->createHostingSupportTicket($tenant, $client, $phone, $session, $account, $lang, $text);
            return;
        }
        if ($step === 'ask_email_name') {
            $this->createHostingMailbox($tenant, $client, $phone, $session, $account, $lang, $text);
            return;
        }
        if ($step === 'upgrade_confirm') {
            if (!preg_match('/^\s*(ndiyo|yes)\s*$/i', $text)) {
                $this->showHostingAccount($tenant, $client, $phone, $account, $lang, multiple: false);
                return;
            }
            $this->createUpgradeInvoiceAndOfferPayment($tenant, $client, $phone, $account, $lang, (string) ($state['plan_id'] ?? ''));
            return;
        }

        // email_menu / upgrade_pick: a number from a list computed when it was shown.
        if (!preg_match('/^\s*([1-9])\s*$/', $text, $m)) {
            $this->reply($tenant, $phone, $this->t($lang, 'Samahani, jibu na namba sahihi kutoka kwenye orodha (au MENU kurudi).', 'Sorry, reply with a valid number from the list (or MENU to go back).'));
            return;
        }
        $n = (int) $m[1];

        if ($step === 'upgrade_pick') {
            $planId = $state['plan_ids'][$n - 1] ?? null;
            $plan = $planId ? $this->upgradePlans($tenant, $account)->firstWhere('plan.id', $planId) : null;
            if (!$plan) {
                $this->reply($tenant, $phone, $this->t($lang, 'Samahani, chagua namba sahihi kutoka kwenye orodha.', 'Sorry, please choose a valid number from the list.'));
                return;
            }
            $this->setHostingState($tenant, $client, $phone, ['step' => 'upgrade_confirm', 'account_id' => $account->id, 'plan_id' => $plan['plan']->id, 'account_ids' => [$account->id]]);
            $this->reply($tenant, $phone, $this->t($lang,
                "*Thibitisha kuboresha {$account->domain}*\n• Kifurushi kipya: {$plan['plan']->name}\n• Utalipa sasa: TZS " . number_format($plan['charge']) . " (sehemu ya muda uliobaki)\n• Hosting haibadilishwi hadi malipo yapokelewe.\nJibu NDIYO kupata invoice, au MENU kusitisha.",
                "*Confirm upgrade for {$account->domain}*\n• New package: {$plan['plan']->name}\n• You pay now: TZS " . number_format($plan['charge']) . " (prorated for the remaining term)\n• Nothing changes until payment is received.\nReply YES to get the invoice, or MENU to cancel."
            ));
            return;
        }

        // email_menu
        $option = $state['options'][$n - 1] ?? null;
        if ($option === 'create') {
            $this->setHostingState($tenant, $client, $phone, ['step' => 'ask_email_name', 'account_id' => $account->id, 'account_ids' => [$account->id]]);
            $this->reply($tenant, $phone, $this->t($lang,
                "Andika jina la email unalotaka (kabla ya @), herufi ndogo, namba, . _ - tu, hadi herufi 32. Mfano: info → info@{$account->domain}",
                "Reply with the email name you want (the part before @): lowercase letters, numbers, . _ - only, up to 32 characters. Example: info → info@{$account->domain}"
            ));
        } elseif ($option === 'forgot') {
            $this->sendEmailPageLink($tenant, $client, $phone, $session, $account, $lang,
                $this->t($lang,
                    "Fungua kiungo hapa chini, chagua email yako, kisha bonyeza \"Manage\" ili kuweka password mpya wewe mwenyewe. Sisi hatubadilishi password kupitia WhatsApp. Kiungo ni cha mara moja; usimtumie mtu.",
                    "Open the link below, pick your email, then tap \"Manage\" to set a new password yourself. We never reset passwords over WhatsApp. The link works once; don't share it."
                ));
        } elseif ($option === 'back') {
            $this->showHostingAccount($tenant, $client, $phone, $account, $lang, multiple: false);
        } else {
            $this->reply($tenant, $phone, $this->t($lang, 'Samahani, chagua namba sahihi kutoka kwenye orodha.', 'Sorry, please choose a valid number from the list.'));
        }
    }

    private function cycleLabel(?string $cycle, string $lang): string
    {
        return match ($cycle) {
            'monthly' => $this->t($lang, 'mwezi', 'month'),
            'quarterly' => $this->t($lang, 'miezi 3', '3 months'),
            'half_yearly' => $this->t($lang, 'miezi 6', '6 months'),
            'yearly' => $this->t($lang, 'mwaka', 'year'),
            default => (string) $cycle,
        };
    }

    /**
     * Plans this account can upgrade to: same tenant, active + portal-visible whm_cpanel, same
     * category and billing cycle, strictly HIGHER price, with a positive prorated charge (same
     * rule as PortalHostingController::upgradeOptions, via PlanChangeService).
     *
     * @return \Illuminate\Support\Collection<int, array{plan: ProductService, charge: float}>
     */
    private function upgradePlans(Tenant $tenant, HostingAccount $account): \Illuminate\Support\Collection
    {
        $sub = $account->subscription;
        $current = $sub ? ProductService::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($sub->product_service_id) : null;
        if (!$sub || !$current) {
            return collect();
        }
        $sub->setRelation('productService', $current);
        $svc = app(\App\Services\Hosting\PlanChangeService::class);

        return ProductService::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->where('is_active', true)
            ->where('portal_visible', true)
            ->where('provisioning_type', 'whm_cpanel')
            ->where('category', $current->category)
            ->where('billing_cycle', $current->billing_cycle)
            ->where('price', '>', $current->price)
            ->where('id', '!=', $current->id)
            ->where(fn ($q) => $q->whereNull('code')->orWhere('code', 'not like', 'WHMCS-P%-%'))
            ->orderBy('price')
            ->get()
            ->unique('name')
            ->map(fn ($p) => ['plan' => $p, 'charge' => $svc->proratedCharge($sub, $p)])
            ->filter(fn ($r) => $r['charge'] > 0)
            ->values()
            ->take(8);
    }

    private function showUpgradeOptions(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, HostingAccount $account, string $lang): void
    {
        $sw = $lang === 'sw';
        if ($account->status !== 'active') {
            $this->reply($tenant, $phone, $this->t($lang, 'Kuboresha kifurushi kunawezekana kwa hosting inayofanya kazi tu.', 'Upgrades are only available for an active hosting account.'));
            return;
        }
        $sub = $account->subscription;
        if (config('whmcs.parallel_mode') && $sub?->legacy_id) {
            $this->reply($tenant, $phone, $this->t($lang, 'Hosting hii haiwezi kubadilishwa mtandaoni bado. Tafadhali wasiliana nasi.', 'This service cannot be changed online yet. Please contact us.'));
            return;
        }

        $plans = $this->upgradePlans($tenant, $account);
        if ($plans->isEmpty()) {
            $this->reply($tenant, $phone, $this->t($lang,
                'Hakuna kifurushi cha juu zaidi kinachopatikana kwa hosting yako sasa. Andika MENU kurudi.',
                'There is no higher package available for your hosting right now. Type MENU to go back.'
            ));
            return;
        }

        $lines = ["*" . ($sw ? "Boresha kifurushi: {$account->domain}" : "Upgrade package: {$account->domain}") . "*"];
        foreach ($plans as $i => $r) {
            $p = $r['plan'];
            $desc = trim(preg_replace('/\s+/', ' ', strip_tags((string) $p->description)));
            $desc = mb_strlen($desc) > 90 ? mb_substr($desc, 0, 87) . '...' : $desc;
            $lines[] = '• ' . ($i + 1) . ") {$p->name} — TZS " . number_format((float) $p->price) . '/' . $this->cycleLabel($p->billing_cycle, $lang)
                . ($desc !== '' ? " — {$desc}" : '')
                . ($sw ? ' — malipo sasa: TZS ' : ' — pay now: TZS ') . number_format($r['charge']);
        }
        $lines[] = $sw ? 'Jibu na namba ya kifurushi, au MENU kurudi.' : 'Reply with the package number, or MENU to go back.';

        $this->setHostingState($tenant, $client, $phone, ['step' => 'upgrade_pick', 'account_id' => $account->id, 'plan_ids' => $plans->pluck('plan.id')->all(), 'account_ids' => [$account->id]]);
        $this->reply($tenant, $phone, implode("\n", $lines));
    }

    private function createUpgradeInvoiceAndOfferPayment(Tenant $tenant, Client $client, string $phone, HostingAccount $account, string $lang, string $planId): void
    {
        $sub = $account->subscription;
        $plan = ($account->status === 'active' && $sub) ? $this->upgradePlans($tenant, $account)->firstWhere('plan.id', $planId) : null;
        if (!$plan) {
            $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, kifurushi hicho hakipatikani tena. Tafadhali jaribu tena.', 'Sorry, that package is no longer available. Please try again.'), $lang);
            return;
        }

        try {
            // Invoice + metadata.pending_plan_change only. The subscription and cPanel package are
            // switched by DocumentObserver -> PlanChangeService::apply() once the invoice is paid.
            $document = app(\App\Services\Hosting\PlanChangeService::class)->createUpgradeInvoice($sub, $plan['plan'], $plan['charge'], $account->domain);
        } catch (\Throwable $e) {
            Log::error('WhatsApp upgrade invoice failed', ['hosting_account_id' => $account->id, 'error' => $e->getMessage()]);
            $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, imeshindikana kutengeneza invoice ya kuboresha. Tafadhali wasiliana nasi.', "Sorry, we couldn't create the upgrade invoice. Please contact us."), $lang);
            return;
        }

        $this->offerPayment($tenant, $client, $phone, $document, $lang);
    }

    // ── Email accounts ───────────────────────────────────────────────────

    private function requireOwnActiveSession(Tenant $tenant, string $phone, WhatsappRenewalSession $session, HostingAccount $account, string $lang, string $what): bool
    {
        if ($session->assisted_by_user_id) {
            $this->reply($tenant, $phone, $this->t($lang,
                "Kwa usalama, {$what} haipatikani kwenye hali ya staff. Tafadhali tumia admin panel.",
                "For security, {$what} is not available in staff-assist mode. Please use the admin panel."
            ));
            return false;
        }
        if ($account->status !== 'active') {
            $this->reply($tenant, $phone, $this->t($lang, 'Huduma hii inapatikana kwa hosting inayofanya kazi tu.', 'This is only available for an active hosting account.'));
            return false;
        }
        return true;
    }

    private function showEmailMenu(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, HostingAccount $account, string $lang): void
    {
        if (!$this->requireOwnActiveSession($tenant, $phone, $session, $account, $lang, $this->t($lang, 'huduma ya email', 'the email service'))) {
            return;
        }
        $this->setHostingState($tenant, $client, $phone, ['step' => 'email_menu', 'account_id' => $account->id, 'options' => ['create', 'forgot', 'back'], 'account_ids' => [$account->id]]);
        $this->reply($tenant, $phone, $this->t($lang,
            "*Email zangu: {$account->domain}*\n• 1) Tengeneza email mpya (jina@{$account->domain})\n• 2) Nimesahau password ya email\n• 3) Rudi\nJibu na namba, au MENU kurudi.",
            "*My email accounts: {$account->domain}*\n• 1) Create a new email (name@{$account->domain})\n• 2) I forgot my email password\n• 3) Back\nReply with a number, or MENU to go back."
        ));
    }

    /** SSO link to cPanel's Email Accounts page. Client's own session only; never logged. */
    private function sendEmailPageLink(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, HostingAccount $account, string $lang, string $text, string $prefix = ''): bool
    {
        if (!$this->requireOwnActiveSession($tenant, $phone, $session, $account, $lang, $this->t($lang, 'kiungo cha cPanel', 'the cPanel link'))) {
            return false;
        }
        try {
            $url = app(\App\Services\Hosting\HostingSsoService::class)->cpanelUrlTo($account, \App\Services\Hosting\HostingSsoService::EMAIL_PAGE);
        } catch (\Throwable $e) {
            Log::warning('WhatsApp email SSO failed', ['client_id' => $client->id, 'hosting_account_id' => $account->id]);
            $this->reply($tenant, $phone, $prefix . $this->t($lang,
                'Samahani, hatuwezi kufungua cPanel kwa sasa. Tafadhali jaribu tena baadaye au wasiliana nasi.',
                "Sorry, we can't open cPanel right now. Please try again later or contact us."
            ));
            return false;
        }
        Log::info('WhatsApp cPanel email SSO link issued', ['client_id' => $client->id, 'hosting_account_id' => $account->id]);
        $this->replyWithCtaUrl($tenant, $phone, $prefix . $text, $this->t($lang, 'Fungua Email', 'Open Email'), $url);
        return true;
    }

    private function createHostingMailbox(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, HostingAccount $account, string $lang, string $text): void
    {
        if (!$this->requireOwnActiveSession($tenant, $phone, $session, $account, $lang, $this->t($lang, 'huduma ya email', 'the email service'))) {
            return;
        }

        $local = strtolower(trim($text));
        if (!preg_match('/^[a-z0-9][a-z0-9._-]{0,31}$/', $local) || str_contains($local, '..')) {
            $this->reply($tenant, $phone, $this->t($lang,
                'Samahani, jina hilo si sahihi. Tumia herufi ndogo, namba, . _ - tu (hadi 32), bila @ na bila nafasi. Jaribu tena, au MENU kurudi.',
                'Sorry, that name is not valid. Use lowercase letters, numbers, . _ - only (up to 32), with no @ and no spaces. Try again, or MENU to go back.'
            ));
            return;
        }

        $mail = app(\App\Services\Hosting\HostingEmailService::class);
        try {
            $usage = $mail->usage($account);
            if ($usage['limit'] !== null && $usage['count'] >= $usage['limit']) {
                $this->reply($tenant, $phone, $this->t($lang,
                    "Umefikia kikomo cha email za kifurushi chako ({$usage['limit']}). Boresha kifurushi au futa email isiyotumika. Andika MENU kurudi.",
                    "You've reached your package's email limit ({$usage['limit']}). Upgrade your package or delete an unused mailbox. Type MENU to go back."
                ));
                return;
            }

            // Random password: known only to the server. It is never messaged or logged; the client
            // sets their own via cPanel.
            $mail->create($account, $local, \Illuminate\Support\Str::password(24));
        } catch (\Throwable $e) {
            Log::warning('WhatsApp mailbox create failed', ['client_id' => $client->id, 'hosting_account_id' => $account->id]);
            $this->reply($tenant, $phone, $this->t($lang,
                'Samahani, imeshindikana kutengeneza email hiyo (huenda jina tayari lipo). Jaribu jina lingine, au MENU kurudi.',
                "Sorry, we couldn't create that email (the name may already exist). Try another name, or MENU to go back."
            ));
            return;
        }

        $address = "{$local}@{$account->domain}";
        $this->sendEmailPageLink($tenant, $client, $phone, $session, $account, $lang,
            $this->t($lang,
                "*Email imetengenezwa: {$address}*\n• Kwa usalama, password haitumwi hapa.\n• Fungua kiungo hapa chini, bonyeza \"Manage\" kwenye {$address}, kisha weka password yako mwenyewe.\n• Kiungo ni cha mara moja; usimtumie mtu.",
                "*Email created: {$address}*\n• For security, the password is not sent here.\n• Open the link below, tap \"Manage\" next to {$address}, then set your own password.\n• The link works once; don't share it."
            ),
            prefix: '');
        $this->sendRootMenu($tenant, $client, $phone, $lang);
    }

    // ── Connect domain to hosting ────────────────────────────────────────

    private function showConnectDomain(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, HostingAccount $account, string $lang): void
    {
        $sw = $lang === 'sw';
        $server = Server::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($account->server_id);
        $ns = array_values(array_filter(array_map(fn ($n) => strtolower(trim((string) $n)),
            ($server?->nameservers && count($server->nameservers)) ? $server->nameservers : (array) config('hosting.default_nameservers', []))));
        $ip = $account->meta['ip'] ?? null;
        if (!$ip && $server) {
            $resolved = @gethostbyname($server->hostname);
            $ip = filter_var($resolved, FILTER_VALIDATE_IP) ? $resolved : null;
        }

        if (!$ns && !$ip) {
            $this->reply($tenant, $phone, $this->t($lang, 'Samahani, hatuna taarifa za nameservers za hosting hii. Tafadhali wasiliana nasi.', "Sorry, we don't have nameserver details for this hosting. Please contact us."));
            return;
        }

        $lines = ["*" . ($sw ? "Unganisha {$account->domain} na hosting" : "Connect {$account->domain} to hosting") . "*"];
        if ($ns) {
            $lines[] = ($sw ? '• Nameservers: ' : '• Nameservers: ') . implode(', ', $ns);
        }
        if ($ip) {
            $lines[] = ($sw ? '• A record (IP ya server): ' : '• A record (server IP): ') . $ip;
        }

        $domain = Domain::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)->where('client_id', $client->id)
            ->where('name', $account->domain)->where('status', 'active')->first();

        if ($domain && count($ns) >= 2) {
            $current = collect($domain->meta['nameservers'] ?? [])->map(fn ($n) => strtolower(is_array($n) ? ($n['name'] ?? '') : (string) $n))->sort()->values()->all();
            $wanted = collect($ns)->sort()->values()->all();
            if ($current === $wanted) {
                $lines[] = $sw ? '• Domain yako tayari inatumia nameservers hizi.' : '• Your domain already uses these nameservers.';
                $this->reply($tenant, $phone, implode("\n", $lines));
                return;
            }

            // Hand off to the EXISTING change-DNS flow at its explicit confirmation step.
            WhatsappRenewalSession::updateOrCreate(
                ['tenant_id' => $tenant->id, 'phone' => $phone],
                ['client_id' => $client->id, 'flow' => 'change_dns', 'state' => ['step' => 'confirm', 'domain_id' => $domain->id, 'nameservers' => $ns], 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(10)],
            );
            $lines[] = $sw
                ? "• {$account->domain} imesajiliwa nasi, tunaweza kubadilisha nameservers kwa niaba yako. Mabadiliko yanaweza kuchukua masaa kadhaa, na email/website ya sasa itaelekezwa kwenye hosting hii."
                : "• {$account->domain} is registered with us, so we can set the nameservers for you. It can take a few hours, and the current website/email will point to this hosting.";
            $lines[] = $sw
                ? 'Jibu NDIYO kubadilisha nameservers, au neno lingine lolote kusitisha.'
                : 'Reply YES to change the nameservers, or anything else to cancel.';
            $this->reply($tenant, $phone, implode("\n", $lines));
            return;
        }

        $lines[] = $sw
            ? '• Domain hii haijasajiliwa nasi: weka nameservers hizi (au A record) kwenye mtoa huduma wa domain yako. Hatuwezi kubadilisha kwa niaba yako.'
            : '• This domain is not registered with us: set these nameservers (or the A record) at your domain registrar. We cannot change them for you.';
        $lines[] = $sw ? 'Andika MENU kurudi.' : 'Type MENU to go back.';
        $this->reply($tenant, $phone, implode("\n", $lines));
    }

    // ── Support tickets ──────────────────────────────────────────────────

    private const WHATSAPP_TICKETS_PER_DAY = 3;
    private const TICKET_MARKER = 'Requested via WhatsApp';

    private function whatsappTicketsLast24h(Tenant $tenant, Client $client): int
    {
        return \App\Models\Ticket::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->where('client_id', $client->id)
            ->where('created_at', '>=', now()->subDay())
            ->whereHas('replies', fn ($q) => $q->withoutGlobalScopes()->where('message', 'like', self::TICKET_MARKER . '%'))
            ->count();
    }

    private function askHostingSupportText(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, HostingAccount $account, string $lang): void
    {
        if ($this->whatsappTicketsLast24h($tenant, $client) >= self::WHATSAPP_TICKETS_PER_DAY) {
            $this->reply($tenant, $phone, $this->t($lang,
                'Umetuma maombi mengi ya msaada leo. Timu yetu inayashughulikia; tafadhali subiri majibu au tupigie simu.',
                "You've sent several support requests today. Our team is working on them; please wait for a reply or call us."
            ));
            return;
        }
        $this->setHostingState($tenant, $client, $phone, ['step' => 'ask_ticket_text', 'account_id' => $account->id, 'account_ids' => [$account->id]]);
        $this->reply($tenant, $phone, $this->t($lang,
            "Eleza tatizo au ombi lako kuhusu {$account->domain} kwa ujumbe mmoja (hadi herufi 500), au MENU kurudi.",
            "Describe your issue or request about {$account->domain} in one message (up to 500 characters), or MENU to go back."
        ));
    }

    private function createHostingSupportTicket(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, HostingAccount $account, string $lang, string $description): void
    {
        $description = trim($description);
        if (mb_strlen($description) < 3 || mb_strlen($description) > 500) {
            $this->reply($tenant, $phone, $this->t($lang,
                'Samahani, ujumbe uwe kati ya herufi 3 na 500 (sasa: ' . mb_strlen($description) . '). Jaribu tena, au MENU kurudi.',
                'Sorry, the message must be between 3 and 500 characters (now: ' . mb_strlen($description) . '). Try again, or MENU to go back.'
            ));
            return;
        }
        if ($this->whatsappTicketsLast24h($tenant, $client) >= self::WHATSAPP_TICKETS_PER_DAY) {
            $this->finishFlow($tenant, $client, $phone, $this->t($lang,
                'Umetuma maombi mengi ya msaada leo. Timu yetu inayashughulikia; tafadhali subiri majibu au tupigie simu.',
                "You've sent several support requests today. Our team is working on them; please wait for a reply or call us."
            ), $lang);
            return;
        }

        try {
            $ticket = \App\Models\Ticket::create([
                'tenant_id' => $tenant->id,
                'client_id' => $client->id,
                'ticket_number' => \App\Models\Ticket::nextNumber($tenant->id),
                'subject' => "Hosting {$account->status}: {$account->domain}",
                'department' => 'support',
                'related_service' => $account->domain,
                'status' => 'open',
                'priority' => $account->status === 'active' ? 'normal' : 'high',
                'last_reply_at' => now(),
            ]);
            $ticket->replies()->create([
                'tenant_id' => $tenant->id,
                'author_type' => 'client',
                'message' => self::TICKET_MARKER . ($session->assisted_by_user_id ? ' (staff-assisted)' : '')
                    . ".\nHosting: {$account->domain} ({$account->cpanel_username}), status: {$account->status}.\n\n" . $description,
            ]);
        } catch (\Throwable $e) {
            Log::warning('WhatsApp hosting support ticket failed', ['client_id' => $client->id, 'hosting_account_id' => $account->id, 'error' => $e->getMessage()]);
            $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, imeshindikana kutuma ujumbe. Tafadhali wasiliana nasi moja kwa moja.', "Sorry, we couldn't send the message. Please contact us directly."), $lang);
            return;
        }

        $this->finishFlow($tenant, $client, $phone, $this->t($lang,
            "Asante, tumepokea ombi lako ({$ticket->ticket_number}) kuhusu {$account->domain}. Timu yetu itakujibu hivi karibuni.",
            "Thanks, we've received your request ({$ticket->ticket_number}) about {$account->domain}. Our team will get back to you shortly."
        ), $lang);
    }

    // ── Renewals (existing domains/hosting already owed) ────────────────

    /**
     * Lists every domain the client has — status and expiry — numbering only the
     * ones actually due (billable) so a reply digit stays unambiguous; the rest are
     * shown for information only.
     */
    private function sendMenu(Tenant $tenant, Client $client, string $phone, RenewalBundleService $bundler, string $lang): void
    {
        $domains = Domain::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->where('client_id', $client->id)
            ->whereIn('status', ['active', 'expired'])
            ->orderBy('name')
            ->get();

        $items = [];
        $lines = [];

        foreach ($domains as $domain) {
            $hostingAccount = HostingAccount::withoutGlobalScopes()
                ->where('tenant_id', $tenant->id)
                ->where('domain', $domain->name)
                ->first();

            try {
                ['billable' => $billable] = $bundler->billableSubscriptions($hostingAccount ?? new HostingAccount([
                    'tenant_id' => $tenant->id,
                    'domain' => $domain->name,
                ]), selfService: true);
            } catch (\Throwable $e) {
                $billable = [];
            }

            if (!empty($billable) && count($items) < 9) {
                $items[] = $domain->id;
                $what = implode(' + ', array_unique(array_map(fn ($s) => $s->productService->category, $billable)));
                // The subscription's own due date (why it's flagged), not the domain
                // registry's expiry — the two frequently disagree (WHMCS-import
                // artifacts), and showing the domain's date here has read as a
                // contradiction ("needs payment" next to an expiry a year out).
                $dueDate = collect($billable)->pluck('expire_date')->filter()->min()?->format('d M Y') ?? '—';
                $lines[] = count($items) . ". {$domain->name} — {$what} " . $this->t($lang, "inahitaji malipo (deadline {$dueDate})", "payment due (deadline {$dueDate})");
            } else {
                $expires = $domain->expires_at?->format('d M Y') ?? '—';
                $lines[] = "• {$domain->name} — " . $this->t($lang, "inaisha {$expires}, hakuna malipo yanayohitajika sasa", "expires {$expires}, nothing due right now");
            }
        }

        if ($domains->isEmpty()) {
            $this->finishFlow($tenant, $client, $phone, $this->t($lang,
                "Habari {$client->name}, huna huduma yoyote iliyosajiliwa kwa sasa. Asante!",
                "Hi {$client->name}, you don't have any services registered with us yet. Thanks!"
            ), $lang);
            return;
        }

        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'items' => $items, 'flow' => null, 'state' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(30)],
        );

        $this->reply($tenant, $phone, $this->t($lang,
            "Habari {$client->name}, huduma zako: " . implode(' · ', $lines) . (!empty($items) ? '. Jibu na namba kulipia huduma inayohitaji malipo.' : '.'),
            "Hi {$client->name}, your services: " . implode(' · ', $lines) . (!empty($items) ? '. Reply with a number to pay for a due service.' : '.')
        ));
    }

    /** Picks items[$position-1] out of $session and bills it, or replies with why it can't. */
    private function pickAndGenerate(Tenant $tenant, ?Client $client, string $phone, WhatsappRenewalSession $session, int $position, RenewalBundleService $bundler, string $lang): void
    {
        $domainId = $session->items[$position - 1] ?? null;
        $client ??= Client::withoutGlobalScopes()->whereNull('deleted_at')->find($session->client_id);
        $session->delete();

        if (!$domainId) {
            $this->replyOrFinish($tenant, $client, $phone, $this->t($lang, 'Samahani, chaguo hilo silo sahihi. Tafadhali jaribu tena.', 'Sorry, that choice is not valid. Please try again.'), $lang);
            return;
        }

        $domain = Domain::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($domainId);
        if (!$domain) {
            $this->replyOrFinish($tenant, $client, $phone, $this->t($lang, 'Samahani, huduma hii haipatikani tena. Tafadhali wasiliana nasi.', 'Sorry, this service is no longer available. Please contact us.'), $lang);
            return;
        }

        $hostingAccount = HostingAccount::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->where('domain', $domain->name)
            ->first();

        try {
            $document = $bundler->generate($hostingAccount ?? new HostingAccount([
                'tenant_id' => $tenant->id,
                'domain' => $domain->name,
            ]), selfService: true);
        } catch (\Throwable $e) {
            $this->replyOrFinish($tenant, $client, $phone, $this->t($lang, "Samahani, {$e->getMessage()}", "Sorry, {$e->getMessage()}"), $lang);
            return;
        }

        if ($client) {
            $this->offerPayment($tenant, $client, $phone, $document, $lang);
        } else {
            $this->replyWithInvoice($tenant, $phone, $document, $lang);
        }
    }

    /** finishFlow() when a client is known (returns to the root menu), a plain reply otherwise. */
    private function replyOrFinish(Tenant $tenant, ?Client $client, string $phone, string $message, string $lang): void
    {
        if ($client) {
            $this->finishFlow($tenant, $client, $phone, $message, $lang);
        } else {
            $this->reply($tenant, $phone, $message);
        }
    }

    // ── New domain registration ─────────────────────────────────────────

    private function startOrderDomain(Tenant $tenant, Client $client, string $phone, string $lang): void
    {
        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'flow' => 'order_domain', 'state' => ['step' => 'ask_name'], 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(10)],
        );

        $this->reply($tenant, $phone, $this->t($lang,
            'Andika jina la domain unalotaka kusajili (mfano: jinalako.co.tz).',
            'Please reply with the domain name you want to register (e.g. yourname.co.tz).'
        ));
    }

    private function handleOrderDomainStep(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, string $text, string $lang): void
    {
        $state = $session->state ?? [];
        $step = $state['step'] ?? 'ask_name';

        if ($step === 'ask_name') {
            $name = strtolower(trim($text));
            if (!preg_match('/^[a-z0-9][a-z0-9.-]+\.[a-z.]{2,}$/', $name)) {
                $this->reply($tenant, $phone, $this->t($lang,
                    'Samahani, jina hilo halionekani sahihi. Andika kama: jinalako.co.tz',
                    "Sorry, that doesn't look like a valid domain. Reply like: yourname.co.tz"
                ));
                return;
            }

            $tld = $this->extractTld($name);
            $pricing = $tld ? DomainTld::priceFor($tenant->id, $tld) : null;

            if (!$pricing || $pricing->is_unmanaged) {
                $this->finishFlow($tenant, $client, $phone, $this->t($lang,
                    'Samahani, aina hii ya domain haiwezi kusajiliwa papo hapo kwa sasa. Tafadhali wasiliana nasi.',
                    "Sorry, this domain type can't be registered instantly right now. Please contact us."
                ), $lang);
                return;
            }

            if (Domain::withoutGlobalScopes()->where('name', $name)->whereNotIn('status', ['cancelled', 'transferred_out'])->exists()) {
                $this->reply($tenant, $phone, $this->t($lang,
                    "Samahani, {$name} tayari imesajiliwa nasi. Andika jina lingine.",
                    "Sorry, {$name} is already registered with us. Please try another name."
                ));
                return;
            }

            try {
                $availability = app(DomainRegistrarManager::class)->driverFor($tenant->id)->check($name);
            } catch (\Throwable $e) {
                Log::warning('WhatsApp order_domain availability check failed', ['name' => $name, 'error' => $e->getMessage()]);
                $this->finishFlow($tenant, $client, $phone, $this->t($lang,
                    'Samahani, imeshindikana kuangalia upatikanaji wa domain hii sasa hivi. Jaribu tena baadaye.',
                    "Sorry, we couldn't check this domain's availability right now. Please try again later."
                ), $lang);
                return;
            }

            if (!($availability['available'] ?? false)) {
                $this->reply($tenant, $phone, $this->t($lang,
                    "Samahani, {$name} tayari imesajiliwa na mwenyewe. Andika jina lingine.",
                    "Sorry, {$name} is already registered by someone else. Please try another name."
                ));
                return;
            }

            $price = (float) $pricing->register_price;
            $session->update(['state' => ['step' => 'confirm', 'domain' => $name, 'price' => $price]]);
            $this->reply($tenant, $phone, $this->t($lang,
                "Domain {$name} inapatikana! Bei: TZS " . number_format($price) . ' kwa mwaka 1. Jibu NDIYO kuagiza.',
                "Domain {$name} is available! Price: TZS " . number_format($price) . ' for 1 year. Reply YES to order.'
            ));
            return;
        }

        if ($step === 'confirm') {
            if (!preg_match('/^\s*(ndiyo|yes)\s*$/i', $text)) {
                $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Sawa, agizo limesitishwa.', 'Okay, the order was cancelled.'), $lang);
                return;
            }

            $domain = $state['domain'] ?? null;
            $price = $state['price'] ?? null;

            if (!$domain || !$price) {
                $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, kuna hitilafu. Tafadhali jaribu tena.', 'Sorry, something went wrong. Please try again.'), $lang);
                return;
            }

            try {
                $document = $this->createDomainOrder($tenant, $client, $domain, (float) $price);
            } catch (\Throwable $e) {
                Log::error('WhatsApp order_domain order creation failed', ['domain' => $domain, 'error' => $e->getMessage()]);
                $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, imeshindikana kutengeneza agizo. Tafadhali wasiliana nasi.', "Sorry, we couldn't create the order. Please contact us."), $lang);
                return;
            }

            // Choosing how to pay comes first; the "want hosting too?" offer (per request
            // — "agiza domain mpya mpaka ku-provision hosting") resumes right after,
            // via offerPayment()'s $after param — a separate invoice (domain registration
            // and hosting are billed independently throughout this app), but one
            // unbroken conversation. Actual provisioning still only fires once each
            // invoice is actually paid (DocumentObserver / ClientSubscriptionObserver →
            // ProvisionHostingAccount), unchanged.
            $this->offerPayment($tenant, $client, $phone, $document, $lang, ['action' => 'offer_hosting', 'domain' => $domain]);
            return;
        }

        if ($step === 'offer_hosting') {
            if (preg_match('/^\s*(ndiyo|yes)\s*$/i', $text)) {
                $this->startOrderHosting($tenant, $client, $phone, 'Web Hosting', $lang, $state['domain'] ?? null);
                return;
            }

            $this->sendRootMenu($tenant, $client, $phone, $lang);
            return;
        }

        $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, kuna hitilafu. Tafadhali jaribu tena.', 'Sorry, something went wrong. Please try again.'), $lang);
    }

    /** Mirrors PortalDomainController::order()'s register path exactly. */
    private function createDomainOrder(Tenant $tenant, Client $client, string $name, float $price, string $action = 'register', ?string $authInfo = null): Document
    {
        $registrar = app(DomainRegistrarManager::class);
        $verb = $action === 'transfer' ? 'transfer' : 'registration';

        return DB::transaction(function () use ($tenant, $client, $name, $price, $registrar, $action, $authInfo, $verb) {
            $document = Document::withoutGlobalScopes()->create([
                'tenant_id' => $tenant->id,
                'client_id' => $client->id,
                'type' => 'invoice',
                'document_number' => app(DocumentNumberService::class)->generate('invoice', $tenant->id),
                'date' => now()->toDateString(),
                'due_date' => now()->addDays(7)->toDateString(),
                'subtotal' => $price,
                'discount_amount' => 0,
                'tax_amount' => 0,
                'total' => $price,
                'status' => 'sent',
                'notes' => "Domain {$verb} (WhatsApp order): {$name} (1 year)",
            ]);

            $document->items()->create([
                'item_type' => 'service',
                'description' => ucfirst($verb) . " domain {$name} — 1 year",
                'quantity' => 1,
                'price' => $price,
                'tax_percent' => 0,
                'tax_amount' => 0,
                'total' => $price,
            ]);

            Domain::reviveOrCreate([
                'tenant_id' => $tenant->id,
                'client_id' => $client->id,
                'registrar_account_id' => $registrar->accountFor($tenant->id)->id,
                'name' => $name,
                'status' => 'pending',
                'auto_renew' => false,
                'epp_auth_info' => $authInfo,
                'meta' => [
                    'pending_action' => $action,
                    'pending_years' => 1,
                    'order_document_id' => $document->id,
                    'whatsapp_order' => true,
                ],
            ]);

            return $document;
        });
    }

    /** Longest-matching TLD suffix against the DomainTld catalog (handles "co.tz" vs "tz"). */
    private function extractTld(string $name): ?string
    {
        $tlds = DomainTld::pluck('tld')->unique();
        $parts = explode('.', $name);

        for ($i = 1; $i < count($parts); $i++) {
            $candidate = implode('.', array_slice($parts, $i));
            if ($tlds->contains($candidate)) {
                return $candidate;
            }
        }

        return null;
    }

    /**
     * @return array{ok: bool, price: ?float, message: ?string}
     * $message is only set when ok=false (already a full bilingual reply string).
     */
    private function checkDomainForOrder(Tenant $tenant, string $name, bool $transfer, string $lang = 'sw'): array
    {
        $tld = $this->extractTld($name);
        $pricing = $tld ? DomainTld::priceFor($tenant->id, $tld) : null;

        if (!$pricing || $pricing->is_unmanaged) {
            return ['ok' => false, 'price' => null, 'message' => $this->t($lang,
                'Samahani, aina hii ya domain haiwezi kushughulikiwa papo hapo kwa sasa. Tafadhali wasiliana nasi.',
                "Sorry, this domain type can't be handled instantly right now. Please contact us."
            )];
        }

        if (!$transfer) {
            if (Domain::withoutGlobalScopes()->where('name', $name)->whereNotIn('status', ['cancelled', 'transferred_out'])->exists()) {
                return ['ok' => false, 'price' => null, 'message' => $this->t($lang,
                    "Samahani, {$name} tayari imesajiliwa nasi. Andika jina lingine.",
                    "Sorry, {$name} is already registered with us. Please try another name."
                )];
            }

            try {
                $availability = app(DomainRegistrarManager::class)->driverFor($tenant->id)->check($name);
            } catch (\Throwable $e) {
                Log::warning('WhatsApp domain check failed', ['name' => $name, 'error' => $e->getMessage()]);
                return ['ok' => false, 'price' => null, 'message' => $this->t($lang,
                    'Samahani, imeshindikana kuangalia upatikanaji wa domain hii sasa hivi. Jaribu tena baadaye.',
                    "Sorry, we couldn't check this domain's availability right now. Please try again later."
                )];
            }

            if (!($availability['available'] ?? false)) {
                return ['ok' => false, 'price' => null, 'message' => $this->t($lang,
                    "Samahani, {$name} tayari imesajiliwa na mwenyewe. Andika jina lingine.",
                    "Sorry, {$name} is already registered by someone else. Please try another name."
                )];
            }
        }

        return ['ok' => true, 'price' => (float) ($transfer ? $pricing->transfer_price : $pricing->register_price), 'message' => null];
    }

    // ── New hosting / business email orders ─────────────────────────────

    /** $prefilledDomain: set when continuing straight from a just-placed domain order — skips ask_domain. */
    private function startOrderHosting(Tenant $tenant, Client $client, string $phone, string $category, string $lang, ?string $prefilledDomain = null): void
    {
        $plans = ProductService::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->where('category', $category)
            ->where('provisioning_type', 'whm_cpanel')
            ->where('is_active', true)
            ->where('portal_visible', true)
            ->orderBy('price')
            ->limit(9)
            ->get();

        if ($plans->isEmpty()) {
            $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, hakuna vifurushi vinavyopatikana kwa sasa. Tafadhali wasiliana nasi.', 'Sorry, no plans are available right now. Please contact us.'), $lang);
            return;
        }

        $planIds = [];
        $lines = [];
        foreach ($plans as $plan) {
            $planIds[] = $plan->id;
            $lines[] = count($planIds) . ". {$plan->name} — TZS " . number_format((float) $plan->price) . "/{$plan->billing_cycle}";
        }

        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'flow' => 'order_hosting', 'state' => ['step' => 'pick_plan', 'category' => $category, 'plan_ids' => $planIds, 'domain' => $prefilledDomain], 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(10)],
        );

        $this->reply($tenant, $phone, $this->t($lang,
            'Chagua kifurushi: ' . implode(' · ', $lines) . '. Jibu na namba.',
            'Choose a plan: ' . implode(' · ', $lines) . '. Reply with a number.'
        ));
    }

    private function handleOrderHostingStep(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, string $text, string $lang): void
    {
        $state = $session->state ?? [];
        $step = $state['step'] ?? 'pick_plan';

        // Picking a number shows that plan's full specs before anything is
        // ordered — the client sees what they'd actually be getting, and can
        // either continue or look at a different numbered option instead.
        if ($step === 'pick_plan' || $step === 'plan_details') {
            if (!preg_match('/^\s*([1-9])\s*$/', $text, $m) || empty($state['plan_ids'][$m[1] - 1])) {
                if ($step === 'plan_details' && preg_match('/^\s*(ndiyo|yes)\s*$/i', $text)) {
                    $plan = ProductService::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($state['product_service_id'] ?? null);
                    if (!$plan) {
                        $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, kifurushi hicho hakipatikani tena. Tafadhali jaribu tena.', 'Sorry, that plan is no longer available. Please try again.'), $lang);
                        return;
                    }

                    // Already have a domain (continuing straight from a domain order) —
                    // skip straight to the promo-code step instead of asking for it again.
                    if (!empty($state['domain'])) {
                        $session->update(['state' => array_merge($state, ['step' => 'ask_promo', 'product_service_id' => $plan->id])]);
                        $this->reply($tenant, $phone, $this->t($lang,
                            'Una promo code? Andika code, au jibu HAPANA kama huna.',
                            'Have a promo code? Reply with the code, or reply NO if you don\'t have one.'
                        ));
                        return;
                    }

                    $session->update(['state' => array_merge($state, ['step' => 'ask_domain_mode', 'product_service_id' => $plan->id])]);
                    $this->reply($tenant, $phone, $this->t($lang,
                        "Umechagua {$plan->name}. Domain: 1) Ninayo tayari (nitaweka DNS mwenyewe) 2) Nisajilie domain mpya 3) Nihamishie (transfer) domain yangu kwenu. Jibu na namba.",
                        "You've chosen {$plan->name}. Domain: 1) I already have one (I'll point the DNS myself) 2) Register a new domain for me 3) Transfer my domain to you. Reply with a number."
                    ));
                    return;
                }

                $this->reply($tenant, $phone, $this->t($lang,
                    'Samahani, chagua namba sahihi kutoka kwenye orodha, au jibu NDIYO kuendelea na kifurushi ulichokwishachagua.',
                    'Sorry, please choose a valid number from the list, or reply YES to continue with the plan you already picked.'
                ));
                return;
            }

            $planId = $state['plan_ids'][$m[1] - 1];
            $plan = ProductService::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($planId);
            if (!$plan) {
                $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, kifurushi hicho hakipatikani tena. Tafadhali jaribu tena.', 'Sorry, that plan is no longer available. Please try again.'), $lang);
                return;
            }

            $session->update(['state' => array_merge($state, ['step' => 'plan_details', 'product_service_id' => $plan->id])]);

            $specs = trim((string) $plan->description) !== '' ? str_replace(["\r\n", "\n"], ' · ', trim($plan->description)) : null;
            $this->reply($tenant, $phone, $this->t($lang,
                "{$plan->name} — TZS " . number_format((float) $plan->price) . "/{$plan->billing_cycle}"
                    . ($specs ? ". {$specs}" : '')
                    . '. Jibu NDIYO kuagiza hiki, au chagua namba nyingine kutoka kwenye orodha ya awali.',
                "{$plan->name} — TZS " . number_format((float) $plan->price) . "/{$plan->billing_cycle}"
                    . ($specs ? ". {$specs}" : '')
                    . '. Reply YES to order this, or choose another number from the earlier list.'
            ));
            return;
        }

        if ($step === 'ask_domain_mode') {
            $plan = ProductService::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($state['product_service_id'] ?? null);
            if (!$plan) {
                $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, kuna hitilafu. Tafadhali jaribu tena.', 'Sorry, something went wrong. Please try again.'), $lang);
                return;
            }

            match (true) {
                (bool) preg_match('/^\s*1\s*$/', $text) => (function () use ($tenant, $phone, $session, $state, $lang) {
                    $session->update(['state' => array_merge($state, ['step' => 'ask_domain'])]);
                    $this->reply($tenant, $phone, $this->t($lang,
                        'Andika jina la domain la huduma hii (lililopo tayari).',
                        'Please reply with the domain name for this service (one you already have).'
                    ));
                })(),
                (bool) preg_match('/^\s*2\s*$/', $text) => (function () use ($tenant, $phone, $session, $state, $lang) {
                    $session->update(['state' => array_merge($state, ['step' => 'register_domain_name'])]);
                    $this->reply($tenant, $phone, $this->t($lang,
                        'Andika jina la domain unalotaka kusajili (mfano: jinalako.co.tz).',
                        'Please reply with the domain name you want to register (e.g. yourname.co.tz).'
                    ));
                })(),
                (bool) preg_match('/^\s*3\s*$/', $text) => (function () use ($tenant, $phone, $session, $state, $lang) {
                    $session->update(['state' => array_merge($state, ['step' => 'transfer_domain_name'])]);
                    $this->reply($tenant, $phone, $this->t($lang,
                        'Andika jina la domain unalotaka kuhamishia kwetu (mfano: jinalako.co.tz).',
                        'Please reply with the domain name you want to transfer to us (e.g. yourname.co.tz).'
                    ));
                })(),
                default => $this->reply($tenant, $phone, $this->t($lang,
                    'Samahani, jibu 1, 2, au 3.',
                    'Sorry, please reply 1, 2, or 3.'
                )),
            };
            return;
        }

        if ($step === 'register_domain_name' || $step === 'transfer_domain_name') {
            $isTransfer = $step === 'transfer_domain_name';
            $name = strtolower(trim($text));
            if (!preg_match('/^[a-z0-9][a-z0-9.-]+\.[a-z.]{2,}$/', $name)) {
                $this->reply($tenant, $phone, $this->t($lang,
                    'Samahani, jina hilo halionekani sahihi. Andika kama: jinalako.co.tz',
                    "Sorry, that doesn't look like a valid domain. Reply like: yourname.co.tz"
                ));
                return;
            }

            ['ok' => $ok, 'price' => $price, 'message' => $message] = $this->checkDomainForOrder($tenant, $name, $isTransfer, $lang);
            if (!$ok) {
                $this->reply($tenant, $phone, $message);
                return;
            }

            if ($isTransfer) {
                $session->update(['state' => array_merge($state, ['step' => 'transfer_domain_auth', 'domain' => $name, 'domain_price' => $price])]);
                $this->reply($tenant, $phone, $this->t($lang,
                    "Bei ya kuhamisha {$name}: TZS " . number_format($price) . ". Andika EPP/Auth code ya domain hii (unaipata kwa msajili wako wa sasa).",
                    "Transfer price for {$name}: TZS " . number_format($price) . ". Please reply with this domain's EPP/Auth code (get it from your current registrar)."
                ));
                return;
            }

            $session->update(['state' => array_merge($state, ['step' => 'register_domain_confirm', 'domain' => $name, 'domain_price' => $price])]);
            $this->reply($tenant, $phone, $this->t($lang,
                "Domain {$name} inapatikana! Bei: TZS " . number_format($price) . ' kwa mwaka 1. Jibu NDIYO kuendelea.',
                "Domain {$name} is available! Price: TZS " . number_format($price) . ' for 1 year. Reply YES to continue.'
            ));
            return;
        }

        if ($step === 'transfer_domain_auth') {
            $authInfo = trim($text);
            if ($authInfo === '') {
                $this->reply($tenant, $phone, $this->t($lang, 'Tafadhali andika EPP/Auth code sahihi.', 'Please reply with a valid EPP/Auth code.'));
                return;
            }

            $session->update(['state' => array_merge($state, ['step' => 'transfer_domain_confirm', 'auth_info' => $authInfo])]);
            $this->reply($tenant, $phone, $this->t($lang,
                "Thibitisha kuhamisha {$state['domain']} — TZS " . number_format((float) $state['domain_price']) . ". Jibu NDIYO kuendelea.",
                "Confirm transferring {$state['domain']} — TZS " . number_format((float) $state['domain_price']) . ". Reply YES to continue."
            ));
            return;
        }

        if ($step === 'register_domain_confirm' || $step === 'transfer_domain_confirm') {
            if (!preg_match('/^\s*(ndiyo|yes)\s*$/i', $text)) {
                $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Sawa, imesitishwa.', 'Okay, cancelled.'), $lang);
                return;
            }

            $isTransfer = $step === 'transfer_domain_confirm';
            $name = $state['domain'] ?? null;
            $price = (float) ($state['domain_price'] ?? 0);
            $plan = ProductService::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($state['product_service_id'] ?? null);

            if (!$name || !$price || !$plan) {
                $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, kuna hitilafu. Tafadhali jaribu tena.', 'Sorry, something went wrong. Please try again.'), $lang);
                return;
            }

            try {
                $document = $this->createDomainOrder($tenant, $client, $name, $price, $isTransfer ? 'transfer' : 'register', $isTransfer ? ($state['auth_info'] ?? null) : null);
            } catch (\Throwable $e) {
                Log::error('WhatsApp hosting-flow domain order creation failed', ['domain' => $name, 'error' => $e->getMessage()]);
                $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, imeshindikana kutengeneza agizo. Tafadhali wasiliana nasi.', "Sorry, we couldn't create the order. Please contact us."), $lang);
                return;
            }

            // Pay for the domain first; the hosting order (same plan already chosen,
            // this domain now known) resumes right after via offerPayment()'s $after.
            $this->offerPayment($tenant, $client, $phone, $document, $lang, [
                'action' => 'continue_hosting',
                'product_service_id' => $plan->id,
                'category' => $state['category'] ?? null,
                'domain' => $name,
            ]);
            return;
        }

        if ($step === 'ask_domain') {
            $name = strtolower(trim($text));
            if (!preg_match('/^[a-z0-9][a-z0-9.-]+\.[a-z.]{2,}$/', $name)) {
                $this->reply($tenant, $phone, $this->t($lang,
                    'Samahani, jina hilo halionekani sahihi. Andika kama: jinalako.co.tz',
                    "Sorry, that doesn't look like a valid domain. Reply like: yourname.co.tz"
                ));
                return;
            }

            $plan = ProductService::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($state['product_service_id'] ?? null);
            if (!$plan) {
                $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, kuna hitilafu. Tafadhali jaribu tena.', 'Sorry, something went wrong. Please try again.'), $lang);
                return;
            }

            $session->update(['state' => array_merge($state, ['step' => 'ask_promo', 'domain' => $name])]);
            $this->reply($tenant, $phone, $this->t($lang,
                'Una promo code? Andika code, au jibu HAPANA kama huna.',
                'Have a promo code? Reply with the code, or reply NO if you don\'t have one.'
            ));
            return;
        }

        if ($step === 'ask_promo') {
            $plan = ProductService::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($state['product_service_id'] ?? null);
            $domain = $state['domain'] ?? null;
            if (!$plan || !$domain) {
                $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, kuna hitilafu. Tafadhali jaribu tena.', 'Sorry, something went wrong. Please try again.'), $lang);
                return;
            }

            if (preg_match('/^\s*(hapana|no|hakuna|skip)\s*$/i', $text)) {
                $session->update(['state' => array_merge($state, ['step' => 'confirm', 'coupon_id' => null])]);
                $this->reply($tenant, $phone, $this->t($lang,
                    "Thibitisha: {$plan->name} — TZS " . number_format((float) $plan->price) . "/{$plan->billing_cycle}, domain: {$domain}. Jibu NDIYO kuagiza.",
                    "Confirm: {$plan->name} — TZS " . number_format((float) $plan->price) . "/{$plan->billing_cycle}, domain: {$domain}. Reply YES to order."
                ));
                return;
            }

            $result = app(CouponService::class)->validateForOrder(trim($text), $tenant->id, $plan, (float) $plan->price, $client->id);
            if ($result['error']) {
                $this->reply($tenant, $phone, $this->t($lang,
                    "Samahani: {$result['error']} Jaribu code nyingine, au jibu HAPANA kuendelea bila punguzo.",
                    "Sorry: {$result['error']} Try another code, or reply NO to continue without a discount."
                ));
                return;
            }

            $coupon = $result['coupon'];
            $discount = (float) $result['discount'];
            $total = max(round((float) $plan->price - $discount, 2), 0);

            $session->update(['state' => array_merge($state, ['step' => 'confirm', 'coupon_id' => $coupon->id])]);
            $this->reply($tenant, $phone, $this->t($lang,
                "Promo {$coupon->code} imekubalika! Punguzo: TZS " . number_format($discount) . ". Thibitisha: {$plan->name} — TZS " . number_format($total) . "/{$plan->billing_cycle}, domain: {$domain}. Jibu NDIYO kuagiza.",
                "Promo {$coupon->code} applied! Discount: TZS " . number_format($discount) . ". Confirm: {$plan->name} — TZS " . number_format($total) . "/{$plan->billing_cycle}, domain: {$domain}. Reply YES to order."
            ));
            return;
        }

        if ($step === 'confirm') {
            if (!preg_match('/^\s*(ndiyo|yes)\s*$/i', $text)) {
                $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Sawa, agizo limesitishwa.', 'Okay, the order was cancelled.'), $lang);
                return;
            }

            $plan = ProductService::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($state['product_service_id'] ?? null);
            $domain = $state['domain'] ?? null;
            $coupon = !empty($state['coupon_id']) ? Coupon::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($state['coupon_id']) : null;

            if (!$plan || !$domain) {
                $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, kuna hitilafu. Tafadhali jaribu tena.', 'Sorry, something went wrong. Please try again.'), $lang);
                return;
            }

            try {
                $document = $this->createHostingOrder($tenant, $client, $plan, $domain, $coupon);
            } catch (CouponUnavailableException) {
                $this->finishFlow($tenant, $client, $phone, $this->t($lang,
                    'Samahani, promo code hiyo imefikia kikomo chake sasa hivi. Tafadhali jaribu tena bila code, au tumia nyingine.',
                    "Sorry, that promo code just reached its usage limit. Please try again without it, or use a different one."
                ), $lang);
                return;
            } catch (\Throwable $e) {
                Log::error('WhatsApp order_hosting order creation failed', ['plan_id' => $plan->id, 'domain' => $domain, 'error' => $e->getMessage()]);
                $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, imeshindikana kutengeneza agizo. Tafadhali wasiliana nasi.', "Sorry, we couldn't create the order. Please contact us."), $lang);
                return;
            }

            $this->offerPayment($tenant, $client, $phone, $document, $lang);
            return;
        }

        $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, kuna hitilafu. Tafadhali jaribu tena.', 'Sorry, something went wrong. Please try again.'), $lang);
    }

    /**
     * Mirrors PortalOrderController::store()'s core sequence for a whm_cpanel
     * product on an existing domain (domain_mode='existing') — no add-ons or
     * config options, not exposed in this chat flow. Coupon discount mirrors
     * that same controller's handling (recomputed server-side here too, never
     * trusting whatever was shown to the client earlier in the conversation).
     */
    private function createHostingOrder(Tenant $tenant, Client $client, ProductService $plan, string $domain, ?Coupon $coupon = null): Document
    {
        return DB::transaction(function () use ($tenant, $client, $plan, $domain, $coupon) {
            $lineBase = round((float) $plan->price, 2);
            $discount = $coupon ? round(min($coupon->discountFor($lineBase, $plan), $lineBase), 2) : 0.0;
            $total = round($lineBase - $discount, 2);

            $subscription = \App\Models\ClientSubscription::withoutGlobalScopes()->create([
                'tenant_id' => $tenant->id,
                'client_id' => $client->id,
                'product_service_id' => $plan->id,
                'label' => $domain,
                'quantity' => 1,
                'status' => 'pending',
                'start_date' => now()->toDateString(),
                'promo_code' => $coupon?->code,
                'metadata' => array_filter([
                    'domain' => $domain,
                    'whatsapp_order' => true,
                    'applied_coupon' => $coupon ? [
                        'coupon_id' => $coupon->id,
                        'code' => $coupon->code,
                        'discount' => $discount,
                        'recurring' => (bool) $coupon->recurring,
                    ] : null,
                ]),
            ]);

            $document = Document::withoutGlobalScopes()->create([
                'tenant_id' => $tenant->id,
                'client_id' => $client->id,
                'type' => 'invoice',
                'document_number' => app(DocumentNumberService::class)->generate('invoice', $tenant->id),
                'date' => now()->toDateString(),
                'due_date' => now()->addDays(7)->toDateString(),
                'subtotal' => $lineBase,
                'discount_amount' => $discount,
                'tax_amount' => 0,
                'total' => $total,
                'status' => 'sent',
                'notes' => "{$plan->name} (WhatsApp order): {$domain}" . ($coupon ? " (promo {$coupon->code})" : ''),
            ]);

            $document->items()->create([
                'item_type' => 'service',
                'description' => "{$plan->name} — {$domain}" . ($discount > 0 ? " (promo {$coupon->code})" : ''),
                'quantity' => 1,
                'price' => $plan->price,
                'discount_type' => $coupon ? $coupon->type : 'percent',
                'discount_value' => $coupon ? (float) $coupon->value : 0,
                'tax_percent' => 0,
                'tax_amount' => 0,
                'total' => $total,
            ]);

            \App\Models\RecurringInvoiceLog::create([
                'tenant_id' => $tenant->id,
                'client_id' => $client->id,
                'client_subscription_id' => $subscription->id,
                'product_service_id' => $plan->id,
                'document_id' => $document->id,
                'next_bill_date' => now()->toDateString(),
            ]);

            // Consume one coupon use atomically — if a concurrent order just raced past
            // max_uses, abort the whole order rather than honor a discount the coupon
            // can no longer back (same guard as PortalOrderController::store()).
            if ($coupon && $discount > 0) {
                $ok = app(CouponService::class)->redeem($coupon, $client->id, $document->id, $discount);
                if (!$ok) {
                    throw new CouponUnavailableException();
                }
            }

            return $document;
        });
    }

    // ── Unpaid invoices ──────────────────────────────────────────────────

    /**
     * Any newly-created invoice (renewal pick, domain order, hosting order) routes through
     * here instead of sending a Pesapal link straight away — the client explicitly chooses
     * online vs offline payment, exactly like picking an invoice from startPayInvoice() does.
     * $after: extra state to resume once payment info has been delivered — currently only
     * used to continue the "want hosting too?" offer after a domain order.
     */
    private function offerPayment(Tenant $tenant, Client $client, string $phone, Document $document, string $lang, ?array $after = null): void
    {
        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'flow' => 'pay_invoice', 'state' => ['step' => 'choose_method', 'document_id' => $document->id, 'after' => $after], 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(10)],
        );

        $this->reply($tenant, $phone, $this->t($lang,
            "Invoice {$document->document_number} — TZS " . number_format((float) $document->total) . '. Chagua njia ya kulipa: 1) Online (Pesapal) · 2) Maelezo ya kulipa (Benki/Lipa Namba). Jibu na namba.',
            "Invoice {$document->document_number} — TZS " . number_format((float) $document->total) . '. Choose how to pay: 1) Online (Pesapal) · 2) Payment details (Bank/mobile money). Reply with a number.'
        ));
    }

    private function startPayInvoice(Tenant $tenant, Client $client, string $phone, string $lang): void
    {
        $invoices = Document::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->where('client_id', $client->id)
            ->where('type', 'invoice')
            ->whereIn('status', ['sent', 'overdue', 'partial'])
            ->orderBy('due_date')
            ->limit(9)
            ->get();

        if ($invoices->isEmpty()) {
            $this->finishFlow($tenant, $client, $phone, $this->t($lang,
                "Habari {$client->name}, huna invoice yoyote isiyolipwa kwa sasa. Asante!",
                "Hi {$client->name}, you have no unpaid invoices right now. Thanks!"
            ), $lang);
            return;
        }

        $docIds = [];
        $lines = [];
        foreach ($invoices as $doc) {
            $docIds[] = $doc->id;
            $balance = number_format((float) $doc->balance_due);
            $due = $doc->due_date?->format('d M Y') ?? '—';
            $lines[] = count($docIds) . ". {$doc->document_number} — TZS {$balance} (deadline {$due})";
        }

        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'flow' => 'pay_invoice', 'state' => ['step' => 'pick_invoice', 'doc_ids' => $docIds], 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(10)],
        );

        $this->reply($tenant, $phone, $this->t($lang,
            'Invoice zako zisizolipwa: ' . implode(' · ', $lines) . '. Jibu na namba kuchagua.',
            'Your unpaid invoices: ' . implode(' · ', $lines) . '. Reply with a number to choose.'
        ));
    }

    private function handlePayInvoiceStep(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, string $text, string $lang): void
    {
        $state = $session->state ?? [];
        $step = $state['step'] ?? 'pick_invoice';

        if ($step === 'pick_invoice') {
            if (!preg_match('/^\s*([1-9])\s*$/', $text, $m) || empty($state['doc_ids'][$m[1] - 1])) {
                $this->reply($tenant, $phone, $this->t($lang, 'Samahani, chagua namba sahihi kutoka kwenye orodha.', 'Sorry, please choose a valid number from the list.'));
                return;
            }

            $docId = $state['doc_ids'][$m[1] - 1];
            $doc = Document::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($docId);
            if (!$doc) {
                $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, invoice hiyo haipatikani tena. Tafadhali jaribu tena.', 'Sorry, that invoice is no longer available. Please try again.'), $lang);
                return;
            }

            $session->update(['state' => ['step' => 'choose_method', 'document_id' => $doc->id]]);
            $this->reply($tenant, $phone, $this->t($lang,
                "Invoice {$doc->document_number} — TZS " . number_format((float) $doc->balance_due) . '. Chagua njia ya kulipa: 1) Online (Pesapal) · 2) Maelezo ya kulipa (Benki/Lipa Namba). Jibu na namba.',
                "Invoice {$doc->document_number} — TZS " . number_format((float) $doc->balance_due) . '. Choose how to pay: 1) Online (Pesapal) · 2) Payment details (Bank/mobile money). Reply with a number.'
            ));
            return;
        }

        if ($step === 'choose_method') {
            $doc = Document::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($state['document_id'] ?? null);
            $after = $state['after'] ?? null;

            if (!$doc) {
                $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, invoice hiyo haipatikani tena. Tafadhali jaribu tena.', 'Sorry, that invoice is no longer available. Please try again.'), $lang);
                return;
            }

            if (preg_match('/^\s*1\s*$/', $text)) {
                if (!$tenant->pesapal_enabled || !$tenant->pesapal_consumer_key) {
                    $this->reply($tenant, $phone, $this->t($lang,
                        'Samahani, malipo ya online hayapatikani kwa sasa. Tuma tena na uchague namba 2 kwa maelezo ya benki.',
                        "Sorry, online payment isn't available right now. Send again and choose 2 for bank details."
                    ));
                    return;
                }
                try {
                    $redirectUrl = $this->pesapalCheckout($tenant, $doc);
                    $this->replyWithCtaUrl(
                        $tenant, $phone,
                        $this->t($lang,
                            'Bonyeza kitufe hapa chini kulipa (namba yako ya simu tayari imejazwa, utapata ombi la PIN moja kwa moja).',
                            "Tap the button below to pay (your phone number is pre-filled — you'll get a PIN prompt right away)."
                        ),
                        $this->t($lang, 'Lipa Sasa', 'Pay Now'),
                        $redirectUrl
                    );
                } catch (\Throwable $e) {
                    Log::warning('WhatsApp pay_invoice Pesapal checkout failed', ['document_id' => $doc->id, 'error' => $e->getMessage()]);
                    $this->reply($tenant, $phone, $this->t($lang, 'Samahani, imeshindikana kutengeneza link ya kulipa. Tafadhali jaribu tena baadaye.', "Sorry, we couldn't create a payment link. Please try again later."));
                }
                $this->afterPayment($tenant, $client, $phone, $lang, $after);
                return;
            }

            if (preg_match('/^\s*2\s*$/', $text)) {
                $this->reply($tenant, $phone, $this->paymentDetailsText($tenant, $lang));
                $this->afterPayment($tenant, $client, $phone, $lang, $after);
                return;
            }

            $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, sikuelewa.', "Sorry, I didn't understand that."), $lang);
            return;
        }

        $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, kuna hitilafu. Tafadhali jaribu tena.', 'Sorry, something went wrong. Please try again.'), $lang);
    }

    /** Resumes whatever offerPayment() was asked to continue with once payment info is delivered. */
    private function afterPayment(Tenant $tenant, Client $client, string $phone, string $lang, ?array $after): void
    {
        if (($after['action'] ?? null) === 'offer_hosting' && !empty($after['domain'])) {
            $domain = $after['domain'];
            WhatsappRenewalSession::updateOrCreate(
                ['tenant_id' => $tenant->id, 'phone' => $phone],
                ['client_id' => $client->id, 'flow' => 'order_domain', 'state' => ['step' => 'offer_hosting', 'domain' => $domain], 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(10)],
            );
            $this->reply($tenant, $phone, $this->t($lang,
                "Je, unataka pia Website Hosting kwenye {$domain}? Jibu NDIYO kuendelea, au namba nyingine kuruka.",
                "Would you also like Website Hosting on {$domain}? Reply YES to continue, or any other number to skip."
            ));
            return;
        }

        if (($after['action'] ?? null) === 'continue_hosting' && !empty($after['product_service_id']) && !empty($after['domain'])) {
            $plan = ProductService::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($after['product_service_id']);
            if ($plan) {
                WhatsappRenewalSession::updateOrCreate(
                    ['tenant_id' => $tenant->id, 'phone' => $phone],
                    ['client_id' => $client->id, 'flow' => 'order_hosting', 'state' => ['step' => 'confirm', 'category' => $after['category'] ?? null, 'product_service_id' => $plan->id, 'domain' => $after['domain']], 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(10)],
                );
                $this->reply($tenant, $phone, $this->t($lang,
                    "Sasa thibitisha hosting: {$plan->name} — TZS " . number_format((float) $plan->price) . "/{$plan->billing_cycle}, domain: {$after['domain']}. Jibu NDIYO kuagiza.",
                    "Now confirm hosting: {$plan->name} — TZS " . number_format((float) $plan->price) . "/{$plan->billing_cycle}, domain: {$after['domain']}. Reply YES to order."
                ));
                return;
            }
        }

        $this->sendRootMenu($tenant, $client, $phone, $lang);
    }

    private function paymentDetailsText(Tenant $tenant, string $lang): string
    {
        // payment_methods (JSON: [{value,label,details:[{key,value}]}]) is the tenant's
        // real, full offline-payment configuration — bank transfer AND mobile money
        // (e.g. MIX BY YAS paybill), not just the older single bank_name/account fields,
        // which only ever covered one bank account.
        $methods = collect($tenant->payment_methods ?? [])
            ->reject(fn ($m) => in_array($m['value'] ?? '', ['pesapal', 'cash', 'cheque'], true))
            ->map(function ($m) {
                $details = collect($m['details'] ?? [])
                    ->map(fn ($d) => "{$d['key']}: {$d['value']}")
                    ->implode(', ');
                return $details !== '' ? "{$m['label']} ({$details})" : null;
            })
            ->filter();

        $fallback = trim(implode(' · ', array_filter([
            $tenant->bank_name ? "Benki: {$tenant->bank_name}" : null,
            $tenant->bank_account_name ? "Jina: {$tenant->bank_account_name}" : null,
            $tenant->bank_account_number ? "Namba: {$tenant->bank_account_number}" : null,
        ])));

        $bank = $methods->isNotEmpty() ? $methods->implode(' · ') : $fallback;
        $bank = trim($bank . ($tenant->payment_instructions ? ' · ' . $tenant->payment_instructions : ''));

        if ($bank === '') {
            return $this->t($lang, 'Tafadhali wasiliana nasi kwa maelezo ya kulipa.', 'Please contact us for payment details.');
        }

        return $this->t($lang,
            "Lipa kupitia: {$bank}. Baada ya kulipa, tuma risiti/screenshot kwetu — malipo yataidhinishwa na wafanyakazi wetu, si moja kwa moja.",
            "Pay via: {$bank}. After paying, please send us the receipt/screenshot — this payment needs to be approved by our staff, it isn't confirmed automatically."
        );
    }

    // ── WHOIS lookup ─────────────────────────────────────────────────────

    private function startWhois(Tenant $tenant, Client $client, string $phone, string $lang): void
    {
        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'flow' => 'whois', 'state' => ['step' => 'ask_name'], 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(10)],
        );

        $this->reply($tenant, $phone, $this->t($lang,
            'Andika jina la domain (.tz) unalotaka kuangalia taarifa zake (mfano: jinalako.co.tz).',
            'Please reply with the .tz domain name you want to look up (e.g. yourname.co.tz).'
        ));
    }

    private function handleWhoisStep(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, string $text, string $lang): void
    {
        $whois = app(TznicWhoisService::class);
        $name = $whois->normalise(strtolower(trim($text)));

        if (!str_ends_with($name, '.tz') || substr_count($name, '.') < 1) {
            $this->reply($tenant, $phone, $this->t($lang,
                'Samahani, andika jina la domain la .tz, mfano: jinalako.co.tz',
                'Sorry, please reply with a .tz domain name, e.g. yourname.co.tz'
            ));
            return;
        }

        try {
            $info = $whois->lookup($name);
        } catch (\Throwable $e) {
            Log::warning('WhatsApp WHOIS lookup failed', ['name' => $name, 'error' => $e->getMessage()]);
            $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, imeshindikana kupata taarifa za domain hii sasa hivi. Jaribu tena baadaye.', "Sorry, we couldn't fetch this domain's information right now. Please try again later."), $lang);
            return;
        }

        if (!($info['found'] ?? false)) {
            $this->finishFlow($tenant, $client, $phone, $this->t($lang, "Domain {$name} haijasajiliwa.", "Domain {$name} is not registered."), $lang);
            return;
        }

        $this->finishFlow($tenant, $client, $phone, implode(' · ', array_filter([
            "Domain: {$name}",
            $info['registrar'] ? $this->t($lang, "Msajili: {$info['registrar']}", "Registrar: {$info['registrar']}") : null,
            $info['registered'] ? $this->t($lang, "Ilisajiliwa: {$info['registered']}", "Registered: {$info['registered']}") : null,
            $info['expire'] ? $this->t($lang, "Inaisha: {$info['expire']}", "Expires: {$info['expire']}") : null,
            !empty($info['nameservers']) ? 'Nameservers: ' . implode(', ', $info['nameservers']) : null,
        ])), $lang);
    }

    // ── Standalone availability check ───────────────────────────────────

    private function startCheckAvailability(Tenant $tenant, Client $client, string $phone, string $lang): void
    {
        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'flow' => 'check_availability', 'state' => ['step' => 'ask_name'], 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(10)],
        );

        $this->reply($tenant, $phone, $this->t($lang,
            'Andika jina la domain unalotaka kuangalia kama linapatikana (mfano: jinalako.co.tz).',
            'Please reply with the domain name you want to check (e.g. yourname.co.tz).'
        ));
    }

    private function handleCheckAvailabilityStep(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, string $text, string $lang): void
    {
        $name = strtolower(trim($text));
        if (!preg_match('/^[a-z0-9][a-z0-9.-]+\.[a-z.]{2,}$/', $name)) {
            $this->reply($tenant, $phone, $this->t($lang,
                'Samahani, jina hilo halionekani sahihi. Andika kama: jinalako.co.tz',
                "Sorry, that doesn't look like a valid domain. Reply like: yourname.co.tz"
            ));
            return;
        }

        $tld = $this->extractTld($name);
        $pricing = $tld ? DomainTld::priceFor($tenant->id, $tld) : null;

        if (!$pricing || $pricing->is_unmanaged) {
            $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, hatuwezi kuangalia aina hii ya domain papo hapo. Tafadhali wasiliana nasi.', "Sorry, we can't check this domain type instantly. Please contact us."), $lang);
            return;
        }

        try {
            $availability = app(DomainRegistrarManager::class)->driverFor($tenant->id)->check($name);
        } catch (\Throwable $e) {
            Log::warning('WhatsApp check_availability failed', ['name' => $name, 'error' => $e->getMessage()]);
            $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, imeshindikana kuangalia domain hii sasa hivi. Jaribu tena baadaye.', "Sorry, we couldn't check this domain right now. Please try again later."), $lang);
            return;
        }

        if ($availability['available'] ?? false) {
            $price = number_format((float) $pricing->register_price);
            $this->finishFlow($tenant, $client, $phone, $this->t($lang,
                "Domain {$name} INAPATIKANA! Bei ya kusajili: TZS {$price}/mwaka. Chagua namba 1 kuagiza.",
                "Domain {$name} is AVAILABLE! Registration price: TZS {$price}/year. Choose option 1 to order it."
            ), $lang);
        } else {
            $this->finishFlow($tenant, $client, $phone, $this->t($lang, "Domain {$name} tayari limesajiliwa — halipatikani.", "Domain {$name} is already registered — not available."), $lang);
        }
    }

    // ── Nameserver / DNS change ─────────────────────────────────────────

    private function startChangeDns(Tenant $tenant, Client $client, string $phone, string $lang): void
    {
        $domains = Domain::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->where('client_id', $client->id)
            ->whereIn('status', ['active', 'expired'])
            ->orderBy('name')
            ->limit(9)
            ->get();

        if ($domains->isEmpty()) {
            $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Huna domain iliyosajiliwa kwa sasa.', "You don't have any registered domains right now."), $lang);
            return;
        }

        $domainIds = $domains->pluck('id')->all();
        $lines = $domains->values()->map(fn ($d, $i) => ($i + 1) . ". {$d->name}")->implode(' · ');

        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'flow' => 'change_dns', 'state' => ['step' => 'pick_domain', 'domain_ids' => $domainIds], 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(10)],
        );

        $this->reply($tenant, $phone, $this->t($lang,
            "Chagua domain unayotaka kubadilisha nameservers: {$lines}. Jibu na namba.",
            "Choose the domain to change nameservers for: {$lines}. Reply with a number."
        ));
    }

    private function handleChangeDnsStep(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, string $text, string $lang): void
    {
        $state = $session->state ?? [];
        $step = $state['step'] ?? 'pick_domain';

        if ($step === 'pick_domain') {
            if (!preg_match('/^\s*([1-9])\s*$/', $text, $m) || empty($state['domain_ids'][$m[1] - 1])) {
                $this->reply($tenant, $phone, $this->t($lang, 'Samahani, chagua namba sahihi kutoka kwenye orodha.', 'Sorry, please choose a valid number from the list.'));
                return;
            }

            $domain = Domain::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($state['domain_ids'][$m[1] - 1]);
            if (!$domain) {
                $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, domain hiyo haipatikani tena. Tafadhali jaribu tena.', 'Sorry, that domain is no longer available. Please try again.'), $lang);
                return;
            }

            $session->update(['state' => ['step' => 'ask_nameservers', 'domain_id' => $domain->id]]);
            $this->reply($tenant, $phone, $this->t($lang,
                "Andika nameservers mbili au zaidi za {$domain->name}, zikitenganishwa na koma. Mfano: ns1.example.com, ns2.example.com",
                "Please reply with two or more nameservers for {$domain->name}, separated by commas. Example: ns1.example.com, ns2.example.com"
            ));
            return;
        }

        if ($step === 'ask_nameservers') {
            $nameservers = array_values(array_filter(array_map('trim', preg_split('/[,\s]+/', strtolower($text)))));

            if (count($nameservers) < 2 || count($nameservers) > 9 || count($nameservers) !== count(array_unique($nameservers))) {
                $this->reply($tenant, $phone, $this->t($lang,
                    'Samahani, andika nameservers 2 hadi 9, zisizofanana, zikitenganishwa na koma.',
                    'Sorry, please reply with 2 to 9 distinct nameservers, separated by commas.'
                ));
                return;
            }

            foreach ($nameservers as $ns) {
                if (!preg_match('/^(?=.{4,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$/i', $ns)) {
                    $this->reply($tenant, $phone, $this->t($lang,
                        "Samahani, \"{$ns}\" halionekani kama jina sahihi la nameserver. Jaribu tena.",
                        "Sorry, \"{$ns}\" doesn't look like a valid nameserver hostname. Please try again."
                    ));
                    return;
                }
            }

            $session->update(['state' => array_merge($state, ['step' => 'confirm', 'nameservers' => $nameservers])]);
            $this->reply($tenant, $phone, $this->t($lang,
                'Thibitisha: ' . implode(', ', $nameservers) . '. Jibu NDIYO kubadilisha.',
                'Confirm: ' . implode(', ', $nameservers) . '. Reply YES to change.'
            ));
            return;
        }

        if ($step === 'confirm') {
            if (!preg_match('/^\s*(ndiyo|yes)\s*$/i', $text)) {
                $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Sawa, imesitishwa.', 'Okay, cancelled.'), $lang);
                return;
            }

            $domain = Domain::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($state['domain_id'] ?? null);
            $nameservers = $state['nameservers'] ?? [];

            if (!$domain || count($nameservers) < 2) {
                $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, kuna hitilafu. Tafadhali jaribu tena.', 'Sorry, something went wrong. Please try again.'), $lang);
                return;
            }

            if (!in_array($domain->status, ['active', 'expired'], true)) {
                $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, domain hii haiko active kwenye registry kwa sasa. Wasiliana nasi.', 'Sorry, this domain is not active at the registry right now. Please contact us.'), $lang);
                return;
            }

            // Mirrors PortalDomainController::updateNameservers() exactly — unmanaged
            // domains (or no registrar driver) get a manual staff request instead of
            // a live registry call, managed .tz ones go straight through the driver.
            if (($domain->meta['unmanaged'] ?? false) || !str_ends_with($domain->name, '.tz')) {
                $meta = $domain->meta ?? [];
                $meta['pending_nameserver_request'] = [
                    'nameservers' => $nameservers,
                    'requested_at' => now()->toISOString(),
                    'requested_by_whatsapp' => $client->id,
                ];
                $domain->update(['meta' => $meta]);

                \App\Models\DomainLog::create([
                    'tenant_id' => $tenant->id,
                    'domain_id' => $domain->id,
                    'action' => 'nameservers_change_requested_manual',
                    'request' => ['by_whatsapp_client_id' => $client->id, 'nameservers' => $nameservers],
                    'status' => 'success',
                ]);

                try {
                    $staff = \App\Models\User::withPermission($tenant->id, 'domains.renew');
                    if ($staff->isNotEmpty()) {
                        \Illuminate\Support\Facades\Notification::send($staff, new \App\Notifications\DomainManualNameserverChangeRequestedNotification($domain, $nameservers));
                    }
                } catch (\Throwable $e) {
                    report($e);
                }

                $this->finishFlow($tenant, $client, $phone, $this->t($lang,
                    'Ombi limepokelewa. Wafanyakazi wetu watabadilisha kwa mkono — inaweza kuchukua muda.',
                    "Request received. Our staff will apply this change manually — it may take some time."
                ), $lang);
                return;
            }

            if (!$domain->nsset_handle) {
                $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Domain hii haina nameserver set bado — wasiliana nasi.', 'This domain has no nameserver set yet — please contact us.'), $lang);
                return;
            }

            try {
                app(\App\Services\Registrar\NameserverService::class)->update($domain, $nameservers, ['by_whatsapp_client_id' => $client->id]);
            } catch (\Throwable $e) {
                Log::warning('WhatsApp change_dns nameserver update failed', ['domain' => $domain->name, 'error' => $e->getMessage()]);
                $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, registry imekataa mabadiliko — angalia majina au wasiliana nasi.', 'Sorry, the registry rejected the change — please check the hostnames or contact us.'), $lang);
                return;
            }

            $this->finishFlow($tenant, $client, $phone, $this->t($lang,
                'Nameservers zimebadilishwa. Mabadiliko ya DNS yanaweza kuchukua hadi masaa kadhaa kusambaa duniani kote.',
                'Nameservers updated. DNS changes can take up to a few hours to propagate worldwide.'
            ), $lang);
            return;
        }

        $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, kuna hitilafu. Tafadhali jaribu tena.', 'Sorry, something went wrong. Please try again.'), $lang);
    }

    // ── Payment ──────────────────────────────────────────────────────────

    private function replyWithInvoice(Tenant $tenant, string $phone, Document $document, string $lang): void
    {
        $total = number_format((float) $document->total);

        if ($tenant->pesapal_enabled && $tenant->pesapal_consumer_key) {
            try {
                $redirectUrl = $this->pesapalCheckout($tenant, $document);
                $this->replyWithCtaUrl(
                    $tenant, $phone,
                    $this->t($lang,
                        "Invoice {$document->document_number} — TZS {$total}. Bonyeza kitufe hapa chini kulipa (namba yako ya simu tayari imejazwa, utapata ombi la PIN moja kwa moja).",
                        "Invoice {$document->document_number} — TZS {$total}. Tap the button below to pay (your phone number is pre-filled — you'll get a PIN prompt right away)."
                    ),
                    $this->t($lang, 'Lipa Sasa', 'Pay Now'),
                    $redirectUrl
                );
                return;
            } catch (\Throwable $e) {
                Log::warning('WhatsApp Pesapal checkout failed', ['document_id' => $document->id, 'error' => $e->getMessage()]);
                // fall through to bank details below
            }
        }

        $this->reply($tenant, $phone, $this->t($lang,
            "Invoice {$document->document_number} — TZS {$total} imetengenezwa. " . $this->paymentDetailsText($tenant, $lang),
            "Invoice {$document->document_number} — TZS {$total} has been created. " . $this->paymentDetailsText($tenant, $lang)
        ));
    }

    private function pesapalCheckout(Tenant $tenant, Document $document): string
    {
        $merchantRef = 'INV-' . $document->id . '-' . Str::random(6);
        $pesapal = new TenantPesapalService($tenant);

        $result = $pesapal->submitOrder(
            $merchantRef,
            (float) $document->balance_due,
            "Payment for {$document->document_number}",
            [
                'email' => $document->client?->email ?? '',
                'phone' => $document->client?->phone ?? '',
                'first_name' => $document->client?->name ?? '',
                'last_name' => '',
            ],
            $tenant->portalUrl("/pay/{$document->id}")
        );

        PesapalInvoicePayment::create([
            'tenant_id' => $tenant->id,
            'document_id' => $document->id,
            'merchant_reference' => $merchantRef,
            'order_tracking_id' => $result['order_tracking_id'] ?? null,
            'pesapal_redirect_url' => $result['redirect_url'] ?? null,
            'amount' => (float) $document->balance_due,
            'currency' => $tenant->currency ?? 'TZS',
            'status' => 'pending',
        ]);

        if (empty($result['redirect_url'])) {
            throw new \RuntimeException('Pesapal did not return a payment link.');
        }

        return $result['redirect_url'];
    }

    /**
     * Always a reply to something this phone just messaged, so the free-form
     * session path applies — no template wrapper copy.
     */
    private function reply(Tenant $tenant, string $phone, string $message): void
    {
        try {
            app(WhatsAppService::class)->sendSessionText($tenant, $phone, $message);
        } catch (\Throwable $e) {
            Log::warning('WhatsApp renewal reply send failed', ['tenant_id' => $tenant->id, 'phone' => $phone, 'error' => $e->getMessage()]);
        }
    }

    /**
     * A CTA-URL button keeps the payment link inside WhatsApp's own in-app browser instead of a
     * bare URL pasted in a text message — falls back to a plain text link if the button send
     * fails for any reason (e.g. tenant on a WABA that doesn't support interactive messages yet).
     */
    private function replyWithCtaUrl(Tenant $tenant, string $phone, string $text, string $buttonText, string $url): void
    {
        try {
            app(WhatsAppService::class)->sendCtaUrlSession($tenant, $phone, $text, $buttonText, $url);
        } catch (\Throwable $e) {
            Log::warning('WhatsApp CTA-URL reply failed, falling back to plain link', ['tenant_id' => $tenant->id, 'phone' => $phone, 'error' => $e->getMessage()]);
            $this->reply($tenant, $phone, "{$text} {$url}");
        }
    }
}
