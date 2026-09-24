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
use App\Services\Registrar\DomainSuggestService;
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

        // MoSMS sends a bare "1" here for days after a domain-expiry reminder, even when the client is
        // mid-conversation (e.g. "1) Pay online", "1) English", "1) Yes"). If a live session is in a flow
        // (or has no renewal items to act on), it is an ordinary menu digit, not a renewal reply.
        if ($session && !$session->isExpired() && (!empty($session->flow) || empty($session->items))) {
            $request->merge(['text' => '1']);
            return $this->menu($request, $bundler);
        }

        if ($this->inboundRateLimited($tenant, $phone)) {
            return response('OK', 200);
        }

        if (!$session || $session->isExpired() || empty($session->items)) {
            $lang = $session->language ?? 'sw';
            $this->reply($tenant, $phone, $this->t($lang,
                'Samahani, muda wa kujibu umepita. Tafadhali wasiliana nasi au ingia kwenye client portal kufanya renewal. Andika MENU kuona huduma zetu.',
                'Sorry, the reply window has passed. Please contact us or log in to the client portal to renew. Type MENU to see our services.'
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

        if ($this->inboundRateLimited($tenant, $phone)) {
            return response('OK', 200);
        }

        $session = WhatsappRenewalSession::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->where('phone', $phone)
            ->first();

        // MoSMS forwards a marker instead of text for images/audio/documents/etc. The bot only reads
        // text; tell the client, and make sure a human sees it (e.g. a bank-transfer receipt).
        // Session state is deliberately left untouched.
        if (in_array(mb_strtolower($text), ['[media]', '[unsupported]'], true)) {
            $this->handleMediaMessage($tenant, $phone, $session);
            return response('OK', 200);
        }

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

        // MENU / CANCEL / NYUMBANI / ANZA UPYA from any not-yet-verified state (language, registration,
        // surname/email, has_account/want_account): start over from the language choice.
        if ($session && !$session->isExpired() && !$session->confirmed_at
            && preg_match('/^\s*(menu|cancel|nyumbani|anza\s*upya)\s*$/i', $text)) {
            $session->delete();
            $session = null;
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

            // "0) Rudi/Back": flows that own their own 0 (more_services, my_servers, expiring, hosting_manage)
            // step back themselves; every other flow's 0 returns to the main menu, so nothing is a dead end.
            if ($session->flow && trim($text) === '0'
                && in_array($session->flow, ['order_domain', 'order_hosting', 'pay_invoice', 'whois', 'check_availability', 'change_dns', 'hosting_submenu'], true)) {
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
                'more_services' => $this->handleMoreServicesStep($tenant, $client, $phone, $session, $text, $lang),
                'my_servers' => $this->handleMyServersStep($tenant, $client, $phone, $session, $text, $lang),
                'expiring' => $this->handleExpiringStep($tenant, $client, $phone, $session, $text, $lang),
                'my_domains' => $this->handleMyDomainsStep($tenant, $client, $phone, $session, $text, $lang),
                'my_hosting' => $this->handleMyHostingStep($tenant, $client, $phone, $session, $text, $lang),
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

        // A session that ran out says so, once, before we start over (startLanguageSelect replaces it).
        if ($session && $session->isExpired()) {
            $sw = 'Muda wa kikao umeisha, tuanze upya.';
            $en = "Your session timed out, let's start again.";
            $this->reply($tenant, $phone, $session->language ? $this->t($session->language, $sw, $en) : "{$sw}\n{$en}");
        }

        // Every fresh contact picks a language first — mirrors the DStv-style bot the
        // user pointed to — before anything else (registration or identity
        // verification) happens, in either language from that point on.
        $this->startLanguageSelect($tenant, $phone, $clientMatch);

        return response('OK', 200);
    }

    private function handleMediaMessage(Tenant $tenant, string $phone, ?WhatsappRenewalSession $session): void
    {
        $lang = ($session && !$session->isExpired() ? $session->language : null) ?? null;
        $sw = 'Tunapokea ujumbe wa maandishi tu kwa sasa. Kwa risiti au picha, tafadhali wasiliana na staff wetu.';
        $en = 'We only accept text messages for now. For receipts or photos, please contact our staff.';
        $this->reply($tenant, $phone, $lang ? $this->t($lang, $sw, $en) : "{$sw}\n{$en}");

        try {
            $client = null;
            if ($session && $session->client_id) {
                $client = Client::withoutGlobalScopes()->whereNull('deleted_at')->find($session->client_id);
            }
            if (!$client) {
                $q = Client::withoutGlobalScopes()->whereNull('deleted_at')->where('tenant_id', $tenant->id);
                $client = PhoneHelper::wherePhone($q, 'phone', $phone)->first();
            }
            $who = $client ? "{$client->name} ({$phone})" : $phone;
            $note = new \App\Notifications\WhatsappBotAlertNotification(
                'media_received',
                'WhatsApp media received',
                "{$who} sent a photo/document/voice note on WhatsApp that the bot cannot read (possibly a payment receipt). Please check the WhatsApp inbox and follow up.",
                $client ? "/clients/{$client->id}" : '/',
            );
            foreach (['tickets.manage', 'orders.create'] as $perm) {
                $staff = User::withPermission($tenant->id, $perm);
                if ($staff->isNotEmpty()) {
                    \Illuminate\Support\Facades\Notification::send($staff, $note);
                    break;
                }
            }
        } catch (\Throwable $e) {
            report($e);
        }
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
        // Also from the PIN steps (never counted as a wrong PIN).
        if (preg_match('/^\s*(menu|toka|cancel|nyumbani|anza\s*upya)\s*$/i', $text)) {
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

            $lines = ["Wateja " . $matches->count() . " wamepatikana kwa \"{$query}\":", ''];
            $ids = [];
            foreach ($matches->take(9) as $i => $c) {
                $ids[] = $c->id;
                $lines[] = ($i + 1) . ") {$c->name}" . ($c->phone ? " — {$c->phone}" : '');
            }
            $session->update(['state' => array_merge($state, ['step' => 'pick_client', 'match_ids' => $ids])]);
            $lines[] = '';
            $lines[] = 'Jibu na namba kumchagua.';
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
            "Karibu MoBilling! Please select your preferred language to continue. Tafadhali chagua lugha:\n\n1) English\n2) Kiswahili");
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
            "Je, una akaunti ya MoBilling?\n\n1) Ndiyo\n2) Hapana\n\nJibu na namba.",
            "Do you have a MoBilling account?\n\n1) Yes\n2) No\n\nReply with a number."
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
            $yes = $this->parseYesNo($text);
            if ($yes === null) {
                $this->invalidYesNo($tenant, $phone, $lang);
                return;
            }
            if ($yes) {
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
                    "Samahani, hatujaweza kupata akaunti yenye namba hii ya simu. Je, ungependa tukutengenezee akaunti mpya ya MoBilling?\n\n1) Ndiyo\n2) Hapana\n\nJibu na namba.",
                    "Sorry, we couldn't find an account with this phone number. Would you like us to create a new MoBilling account for you?\n\n1) Yes\n2) No\n\nReply with a number."
                ));
                return;
            }

            $session->update(['state' => ['step' => 'want_account']]);
            $this->reply($tenant, $phone, $this->t($lang,
                "Je, ungependa tukutengenezee akaunti ya MoBilling?\n\n1) Ndiyo\n2) Hapana\n\nJibu na namba.",
                "Would you like us to create a MoBilling account for you?\n\n1) Yes\n2) No\n\nReply with a number."
            ));
            return;
        }

        if (($state['step'] ?? '') === 'want_account') {
            $yes = $this->parseYesNo($text);
            if ($yes === null) {
                $this->invalidYesNo($tenant, $phone, $lang);
                return;
            }
            if (!$yes) {
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

    // ── Shared presentation helpers (numbering, confirmations, footers, hints) ──

    /** The two explicit confirmation choices, always the same wording and digits. */
    private function yesNoOptions(string $lang): string
    {
        return $this->t($lang, "1) Ndiyo\n2) Hapana", "1) Yes\n2) No");
    }

    /**
     * Confirmation input: 1 / NDIYO / NDIO / YES / Y => true; 2 / HAPANA / NO / N => false; anything else => null.
     * Confirmations are always their OWN state step, so a digit here can never belong to an earlier list.
     */
    private function parseYesNo(string $text): ?bool
    {
        // Case, spaces, trailing punctuation and emoji are ignored ("Ndiyo.", " YES ", "1)", "ok 👍").
        $t = preg_replace('/[^\p{L}\p{N}]+/u', '', mb_strtolower($text));
        if (in_array($t, ['1', 'ndiyo', 'ndio', 'yes', 'y', 'ok', 'okay', 'sawa'], true)) {
            return true;
        }
        if (in_array($t, ['2', 'hapana', 'no', 'n'], true)) {
            return false;
        }
        return null;
    }

    /** "1, 2 or 0" — spoken form of the digits a step really accepts. */
    private function joinChoices(string $lang, array $nums): string
    {
        $nums = array_values($nums);
        if (count($nums) > 4) {
            // a long consecutive run reads better as a range
            $run = array_values(array_filter($nums, fn ($n) => $n !== 0));
            if ($run && $run === range($run[0], end($run))) {
                $txt = $run[0] . '-' . end($run);
                return in_array(0, $nums, true) ? $txt . $this->t($lang, ' au 0', ' or 0') : $txt;
            }
        }
        $last = array_pop($nums);
        return $nums ? implode(', ', $nums) . $this->t($lang, " au {$last}", " or {$last}") : (string) $last;
    }

    /** Re-prompt for a numbered step: names the digits that are valid RIGHT NOW. */
    private function replyChoice(string $lang, int $count, bool $back = true): string
    {
        $nums = $count > 0 ? range(1, $count) : [];
        if ($back) {
            $nums[] = 0;
        }
        $list = $this->joinChoices($lang, $nums);
        return $this->t($lang, "Samahani, jibu {$list}.", "Sorry, reply {$list}.");
    }

    private function invalidChoice(Tenant $tenant, string $phone, string $lang, int $count, bool $back = true): void
    {
        $this->reply($tenant, $phone, $this->replyChoice($lang, $count, $back));
    }

    private function invalidYesNo(Tenant $tenant, string $phone, string $lang): void
    {
        $this->reply($tenant, $phone, $this->t($lang,
            "Samahani, jibu 1 au 2.\n\n" . $this->yesNoOptions($lang),
            "Sorry, reply 1 or 2.\n\n" . $this->yesNoOptions($lang)
        ));
    }

    /** Footer for menus and lists. `0` goes back; MENU always goes to the main menu. */
    private function menuFooter(string $lang, bool $back = true): string
    {
        return $this->t($lang,
            ($back ? "0) Rudi\n" : '') . 'Andika MENU kwenda menyu kuu.',
            ($back ? "0) Back\n" : '') . 'Type MENU for the main menu.'
        );
    }

    /** Status dot: 🟢 good, 🔴 stopped/lapsed, 🟡 in progress. */
    private function dot(?string $status): string
    {
        return match ($status) {
            'active', 'running', 'paid' => '🟢',
            'suspended', 'offline', 'failed', 'expired', 'stopped', 'cancelled' => '🔴',
            default => '🟡',
        };
    }

    /** Generic (domain / subscription) status, localised. */
    private function statusLabel(?string $status, string $lang): string
    {
        return match ($status) {
            'active' => $this->t($lang, 'inafanya kazi', 'active'),
            'pending' => $this->t($lang, 'inaandaliwa', 'pending'),
            'suspended' => $this->t($lang, 'imesimamishwa', 'suspended'),
            'expired' => $this->t($lang, 'imeisha muda', 'expired'),
            'cancelled' => $this->t($lang, 'imeghairiwa', 'cancelled'),
            default => (string) $status,
        };
    }

    /** Cloud server power/status, localised (never the raw provider word). */
    private function serverStatusLabel(?string $status, string $lang): string
    {
        return match ($status) {
            'running' => $this->t($lang, 'inafanya kazi', 'Running'),
            'offline' => $this->t($lang, 'imezimwa', 'Off'),
            'rebooting' => $this->t($lang, 'inawashwa upya', 'Rebooting'),
            'booting' => $this->t($lang, 'inawashwa', 'Starting'),
            'shutting_down' => $this->t($lang, 'inazimwa', 'Shutting down'),
            'provisioning' => $this->t($lang, 'inaandaliwa', 'Being set up'),
            'migrating' => $this->t($lang, 'inahamishwa', 'Moving'),
            'resizing' => $this->t($lang, 'inabadilishwa ukubwa', 'Resizing'),
            'rebuilding' => $this->t($lang, 'inajengwa upya', 'Rebuilding'),
            'busy' => $this->t($lang, 'iko na shughuli', 'Busy'),
            null, '' => '—',
            default => ucfirst(str_replace('_', ' ', (string) $status)),
        };
    }

    /**
     * Note under a capped list: how many more exist and how to reach them. Where the step can
     * search ($search) the client types a name; otherwise they're pointed at the portal.
     */
    private function moreNotice(Tenant $tenant, string $lang, int $more, bool $search, string $portalPath = '/portal'): string
    {
        if ($more <= 0) {
            return '';
        }
        if ($search) {
            return "\n" . $this->t($lang, "Zipo nyingine {$more}. Andika jina kutafuta.", "There are {$more} more. Type a name to search.");
        }
        $url = $tenant->portalUrl($portalPath);
        return "\n" . $this->t($lang, "Zipo nyingine {$more}. Tembelea portal kuona zote: {$url}", "There are {$more} more. Visit the portal to see all: {$url}");
    }

    /**
     * THE "domain is available" message (order flow, hosting-with-domain flow, search-row pick and the
     * single-domain check all render through here). $mode 'order' asks to order now; 'continue'
     * asks to continue with the hosting order it belongs to.
     */
    private function availableDomainMessage(string $lang, string $name, float $price, string $mode = 'order'): string
    {
        $q = $mode === 'continue'
            ? $this->t($lang, 'Endelea?', 'Continue?')
            : $this->t($lang, 'Unataka kuagiza sasa?', 'Order it now?');

        return $this->t($lang,
            "✅ *{$name}* inapatikana\nBei: TZS " . number_format($price) . " kwa mwaka 1\n\n{$q}\n" . $this->yesNoOptions($lang),
            "✅ *{$name}* is available\nPrice: TZS " . number_format($price) . " for 1 year\n\n{$q}\n" . $this->yesNoOptions($lang)
        );
    }

    /** Summary block: a bold title, bullet lines, then the 1)/2) choices. */
    private function confirmMessage(string $lang, string $title, array $bullets, ?string $question = null): string
    {
        $out = "*{$title}*\n" . implode("\n", array_map(fn ($b) => "• {$b}", array_filter($bullets)));
        return $out . "\n\n" . ($question ? $question . "\n" : '') . $this->yesNoOptions($lang);
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
            "Habari {$client->name}! 👋\n*Chagua huduma:*\n\n"
                . "*Domain*\n"
                . "1) Domain Registration\n"
                . "2) Domain Renewal\n"
                . "6) WHOIS ya Domain\n"
                . "7) Angalia kama Domain Inapatikana\n"
                . "8) Badilisha Nameservers (DNS)\n"
                . "11) Domain Zangu\n\n"
                . "*Hosting na Email*\n"
                . "3) Website Hosting\n"
                . "4) Business Email Hosting\n"
                . "12) Hosting Yangu\n\n"
                . "*Malipo*\n"
                . "5) Angalia na Lipa Invoice\n\n"
                . "*Akaunti*\n"
                . "9) Taarifa za Akaunti\n"
                . "10) Huduma Zaidi\n"
                . "0) Toka (Logout)\n\n"
                . "Jibu na namba.\n"
                . 'Andika MOSMS kwa huduma za akaunti yako ya SMS/WhatsApp bulk.',
            "Hi {$client->name}! 👋\n*Choose a service:*\n\n"
                . "*Domains*\n"
                . "1) Domain Registration\n"
                . "2) Domain Renewal\n"
                . "6) Domain WHOIS\n"
                . "7) Check Domain Availability\n"
                . "8) Change Nameservers (DNS)\n"
                . "11) My Domains\n\n"
                . "*Hosting & Email*\n"
                . "3) Website Hosting\n"
                . "4) Business Email Hosting\n"
                . "12) My Hosting\n\n"
                . "*Payments*\n"
                . "5) View and Pay Invoices\n\n"
                . "*Account*\n"
                . "9) Account Information\n"
                . "10) More services\n"
                . "0) Logout\n\n"
                . "Reply with a number.\n"
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
                $lines[] = "{$this->dot($d->status)} {$d->name} — " . $this->statusLabel($d->status, $lang) . ', ' . ($sw ? "inaisha {$exp}" : "expires {$exp}");
            }
        }

        if ($subscriptions->isNotEmpty()) {
            $lines[] = "\n" . ($sw ? '*Huduma (' : '*Services (') . $subscriptions->count() . '):*';
            foreach ($subscriptions as $s) {
                $exp = $s->expire_date ? $s->expire_date->format('d M Y') : '—';
                $name = $s->productService?->name ?? ($sw ? 'Huduma' : 'Service');
                $lines[] = "{$this->dot($s->status)} {$name}" . ($s->label ? " — {$s->label}" : '') . ' — ' . $this->statusLabel($s->status, $lang) . ', ' . ($sw ? "inaisha {$exp}" : "expires {$exp}");
            }
        }

        $lines[] = "\n" . ($sw ? '*Deni linalodaiwa:* TZS ' : '*Outstanding balance:* TZS ') . number_format($balanceDue);

        $this->reply($tenant, $phone, implode("\n", $lines));
    }

    private function logout(Tenant $tenant, string $phone, string $lang): void
    {
        WhatsappRenewalSession::where('tenant_id', $tenant->id)->where('phone', $phone)->delete();
        $this->reply($tenant, $phone, $this->t($lang,
            'Umetoka. Andika MOBILLING kuanza tena.',
            'You have logged out. Type MOBILLING to start again.'
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
        // Renewal picker already active: 0 = Rudi (back to the main menu, not logout).
        if (!empty($session->items) && trim($text) === '0') {
            $this->sendRootMenu($tenant, $client, $phone, $lang);
            return;
        }

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
            (bool) preg_match('/^\s*10\s*$/', $text) => $this->startMoreServices($tenant, $client, $phone, $lang),
            (bool) preg_match('/^\s*11\s*$/', $text) => $this->startMyDomains($tenant, $client, $phone, $lang),
            (bool) preg_match('/^\s*12\s*$/', $text) => $this->startMyHosting($tenant, $client, $phone, $lang),
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
            "*Website Hosting*\n\n1) Agiza hosting mpya\n2) Hosting yangu (hali, cPanel, malipo)\n\n" . $this->menuFooter($lang),
            "*Website Hosting*\n\n1) Order new hosting\n2) My hosting (status, cPanel, payment)\n\n" . $this->menuFooter($lang)
        ));
    }

    private function handleHostingSubmenuStep(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, string $text, string $lang): void
    {
        if (preg_match('/^\s*1\s*$/', $text)) {
            $this->startOrderHosting($tenant, $client, $phone, 'Web Hosting', $lang);
        } elseif (preg_match('/^\s*2\s*$/', $text)) {
            $this->startHostingManage($tenant, $client, $phone, $lang);
        } else {
            $this->invalidChoice($tenant, $phone, $lang, 2);
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

    private function startHostingManage(Tenant $tenant, Client $client, string $phone, string $lang, ?string $query = null): void
    {
        $base = $this->clientHostingAccounts($tenant, $client);
        if ($query !== null) {
            $base->where('hosting_accounts.domain', 'like', '%' . addcslashes($query, '%_\\') . '%');
        }
        $total = (clone $base)->count();
        $accounts = $base->limit(9)->get();

        if ($accounts->isEmpty() && $query !== null) {
            $this->reply($tenant, $phone, $this->t($lang,
                "Hakuna hosting inayolingana na \"{$query}\". Jaribu jina lingine, au:\n\n" . $this->menuFooter($lang),
                "No hosting matches \"{$query}\". Try another name, or:\n\n" . $this->menuFooter($lang)
            ));
            return;
        }

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
            $lines[] = ($i + 1) . ") {$this->dot($a->status)} {$a->domain} — " . $this->hostingStatusLabel($a->status, $lang);
        }

        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'flow' => 'hosting_manage', 'state' => ['step' => 'pick_account', 'account_ids' => $accounts->pluck('id')->all(), 'capped' => $total > $accounts->count()], 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(10)],
        );

        $this->reply($tenant, $phone, $this->t($lang,
            "*Hosting yako* — chagua akaunti\n\n" . implode("\n", $lines) . $this->moreNotice($tenant, $lang, $total - $accounts->count(), true) . "\n\n" . $this->menuFooter($lang),
            "*Your hosting* — choose an account\n\n" . implode("\n", $lines) . $this->moreNotice($tenant, $lang, $total - $accounts->count(), true) . "\n\n" . $this->menuFooter($lang)
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

        // 0) Rudi / Back
        if (trim($text) === '0') {
            if ($step === 'account_menu' && in_array('back', $state['options'] ?? [], true)) {
                $this->startHostingManage($tenant, $client, $phone, $lang);
            } else {
                $this->sendRootMenu($tenant, $client, $phone, $lang);
            }
            return;
        }

        // A capped account list: a typed name (not a digit) searches ALL of the client's hosting.
        if ($step === 'pick_account' && !empty($state['capped']) && !preg_match('/^\s*\d+\s*$/', $text) && mb_strlen(trim($text)) >= 2) {
            $this->startHostingManage($tenant, $client, $phone, $lang, trim($text));
            return;
        }

        if (!preg_match('/^\s*([1-9])\s*$/', $text, $m)) {
            $this->invalidChoice($tenant, $phone, $lang, $step === 'pick_account' ? count($state['account_ids'] ?? []) : count($state['options'] ?? []));
            return;
        }
        $n = (int) $m[1];

        if ($step === 'pick_account') {
            $id = $state['account_ids'][$n - 1] ?? null;
            $account = $id ? $this->clientHostingAccounts($tenant, $client)->where('hosting_accounts.id', $id)->first() : null;
            if (!$account) {
                $this->invalidChoice($tenant, $phone, $lang, count($state['account_ids'] ?? []));
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
            $this->invalidChoice($tenant, $phone, $lang, count($state['options'] ?? []));
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
        $lines[] = ($sw ? '• Hali: ' : '• Status: ') . $this->dot($account->status) . ' ' . $this->hostingStatusLabel($account->status, $lang) . ($meaning ? " — {$meaning}" : '');
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
            $msg .= "\n\n" . ($sw ? "Chagua:\n" : "Choose:\n") . implode("\n", $optLines) . "\n\n" . $this->menuFooter($lang);
        } else {
            $msg .= "\n\n" . $this->menuFooter($lang);
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

        // 0) Rudi / Back — to this account's own menu
        if (trim($text) === '0') {
            $this->showHostingAccount($tenant, $client, $phone, $account, $lang, multiple: false);
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
            $yes = $this->parseYesNo($text);
            if ($yes === null) {
                $this->invalidYesNo($tenant, $phone, $lang);
                return;
            }
            if (!$yes) {
                $this->showHostingAccount($tenant, $client, $phone, $account, $lang, multiple: false);
                return;
            }
            $this->createUpgradeInvoiceAndOfferPayment($tenant, $client, $phone, $account, $lang, (string) ($state['plan_id'] ?? ''));
            return;
        }

        // email_menu / upgrade_pick: a number from a list computed when it was shown.
        $listCount = $step === 'upgrade_pick' ? count($state['plan_ids'] ?? []) : count($state['options'] ?? []);
        if (!preg_match('/^\s*([1-9])\s*$/', $text, $m)) {
            $this->invalidChoice($tenant, $phone, $lang, $listCount);
            return;
        }
        $n = (int) $m[1];

        if ($step === 'upgrade_pick') {
            $planId = $state['plan_ids'][$n - 1] ?? null;
            $plan = $planId ? $this->upgradePlans($tenant, $account)->firstWhere('plan.id', $planId) : null;
            if (!$plan) {
                $this->invalidChoice($tenant, $phone, $lang, $listCount);
                return;
            }
            $this->setHostingState($tenant, $client, $phone, ['step' => 'upgrade_confirm', 'account_id' => $account->id, 'plan_id' => $plan['plan']->id, 'account_ids' => [$account->id]]);
            $this->reply($tenant, $phone,
                $this->t($lang,
                    $this->confirmMessage('sw', "Thibitisha kuboresha {$account->domain}", [
                        "Kifurushi kipya: {$plan['plan']->name}",
                        'Utalipa sasa: TZS ' . number_format($plan['charge']) . ' (sehemu ya muda uliobaki)',
                        'Hosting haibadilishwi hadi malipo yapokelewe.',
                    ], 'Unataka kupata invoice?'),
                    $this->confirmMessage('en', "Confirm upgrade for {$account->domain}", [
                        "New package: {$plan['plan']->name}",
                        'You pay now: TZS ' . number_format($plan['charge']) . ' (prorated for the remaining term)',
                        'Nothing changes until payment is received.',
                    ], 'Get the invoice?')
                ));
            return;
        }

        // email_menu
        $option = $state['options'][$n - 1] ?? null;
        if ($option === 'create') {
            $this->setHostingState($tenant, $client, $phone, ['step' => 'ask_email_name', 'account_id' => $account->id, 'account_ids' => [$account->id]]);
            $this->reply($tenant, $phone, $this->t($lang,
                "Andika jina la email unalotaka (kabla ya @), herufi ndogo, namba, . _ - tu, hadi herufi 32. Mfano: info → info@{$account->domain}\n\n" . $this->menuFooter($lang),
                "Reply with the email name you want (the part before @): lowercase letters, numbers, . _ - only, up to 32 characters. Example: info → info@{$account->domain}\n\n" . $this->menuFooter($lang)
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
            $this->invalidChoice($tenant, $phone, $lang, $listCount);
        }
    }

    private function cycleLabel(?string $cycle, string $lang): string
    {
        return match ($cycle) {
            'monthly' => $this->t($lang, 'kwa mwezi', 'per month'),
            'quarterly' => $this->t($lang, 'kwa miezi 3', 'per 3 months'),
            'half_yearly' => $this->t($lang, 'kwa miezi 6', 'per 6 months'),
            'yearly', 'annually' => $this->t($lang, 'kwa mwaka', 'per year'),
            'one_time', 'onetime' => $this->t($lang, 'mara moja', 'one-time'),
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
                "Hakuna kifurushi cha juu zaidi kinachopatikana kwa hosting yako sasa.\n\n" . $this->menuFooter($lang),
                "There is no higher package available for your hosting right now.\n\n" . $this->menuFooter($lang)
            ));
            return;
        }

        $lines = ["*" . ($sw ? "Boresha kifurushi: {$account->domain}" : "Upgrade package: {$account->domain}") . "*", ''];
        foreach ($plans as $i => $r) {
            $p = $r['plan'];
            $desc = trim(preg_replace('/\s+/', ' ', strip_tags((string) $p->description)));
            $desc = mb_strlen($desc) > 90 ? mb_substr($desc, 0, 87) . '...' : $desc;
            $lines[] = ($i + 1) . ") {$p->name} — TZS " . number_format((float) $p->price) . ' ' . $this->cycleLabel($p->billing_cycle, $lang)
                . ($desc !== '' ? " — {$desc}" : '')
                . ($sw ? ' — malipo sasa: TZS ' : ' — pay now: TZS ') . number_format($r['charge']);
        }
        $lines[] = '';
        $lines[] = $sw ? 'Jibu na namba ya kifurushi.' : 'Reply with the package number.';
        $lines[] = $this->menuFooter($lang);

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

    // ── "10) More services" submenu: My Servers, Expiring soon ──────────
    // Everything here is client-facing: neutral wording only ("Cloud Server"), never a supplier
    // name or a cost. Reads local data; the ONLY live call is the reboot's status check + POST.

    private const SERVER_REBOOT_PER_SERVER_HOUR = 2;
    private const SERVER_REBOOT_PER_CLIENT_DAY = 5;
    private const SERVER_REBOOT_PER_TENANT_HOUR = 20;
    private const EXPIRING_AHEAD_DAYS = 60;
    private const EXPIRING_BEHIND_DAYS = 30;
    private const EXPIRING_MAX = 10;

    private function isBackWord(string $text): bool
    {
        return (bool) preg_match('/^\s*(0|back|rudi)\s*$/i', $text);
    }

    private function startMoreServices(Tenant $tenant, Client $client, string $phone, string $lang): void
    {
        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'flow' => 'more_services', 'state' => ['step' => 'choose'], 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(10)],
        );

        $this->reply($tenant, $phone, $this->t($lang,
            "*Huduma Zaidi*\n\n1) Server Zangu (Cloud Server)\n2) Zinazokaribia kuisha\n3) Msaada\n\n" . $this->menuFooter($lang),
            "*More services*\n\n1) My Servers (Cloud Server)\n2) Expiring soon\n3) Support\n\n" . $this->menuFooter($lang)
        ));
    }

    private function handleMoreServicesStep(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, string $text, string $lang): void
    {
        // 3) Msaada / Support: the free-text description step.
        if (($session->state['step'] ?? '') === 'support_text') {
            if ($this->isBackWord($text)) {
                $this->startMoreServices($tenant, $client, $phone, $lang);
                return;
            }
            $this->createGeneralSupportTicket($tenant, $client, $phone, $session, $text, $lang);
            return;
        }

        if ($this->isBackWord($text)) {
            $this->sendRootMenu($tenant, $client, $phone, $lang);
        } elseif (preg_match('/^\s*1\s*$/', $text)) {
            $this->startMyServers($tenant, $client, $phone, $lang);
        } elseif (preg_match('/^\s*2\s*$/', $text)) {
            $this->startExpiring($tenant, $client, $phone, $lang);
        } elseif (preg_match('/^\s*3\s*$/', $text)) {
            $this->askGeneralSupportText($tenant, $client, $phone, $lang);
        } else {
            $this->invalidChoice($tenant, $phone, $lang, 3);
        }
    }

    // ── 3) Msaada / Support (general ticket) ──

    private const SUPPORT_MIN = 5;
    private const SUPPORT_MAX = 1000;

    private function supportLimitMessage(string $lang): string
    {
        return $this->t($lang,
            'Umetuma maombi mengi ya msaada leo (kikomo ni ' . self::WHATSAPP_TICKETS_PER_DAY . ' kwa siku). Timu yetu inayashughulikia; tafadhali subiri majibu au tupigie simu.',
            "You've reached today's support limit (" . self::WHATSAPP_TICKETS_PER_DAY . ' requests per day). Our team is working on them; please wait for a reply or call us.'
        );
    }

    private function askGeneralSupportText(Tenant $tenant, Client $client, string $phone, string $lang): void
    {
        if ($this->whatsappTicketsLast24h($tenant, $client) >= self::WHATSAPP_TICKETS_PER_DAY) {
            Log::info('WhatsApp support request refused (daily limit)', ['tenant_id' => $tenant->id, 'client_id' => $client->id]);
            $this->finishFlow($tenant, $client, $phone, $this->supportLimitMessage($lang), $lang);
            return;
        }

        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'flow' => 'more_services', 'state' => ['step' => 'support_text'], 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(10)],
        );

        $this->reply($tenant, $phone, $this->t($lang,
            "*Msaada*\nEleza tatizo au ombi lako kwa ujumbe mmoja (herufi " . self::SUPPORT_MIN . ' hadi ' . self::SUPPORT_MAX . ").\n\n" . $this->menuFooter($lang),
            "*Support*\nDescribe your issue or request in one message (" . self::SUPPORT_MIN . ' to ' . self::SUPPORT_MAX . " characters).\n\n" . $this->menuFooter($lang)
        ));
    }

    /**
     * Same records the portal's PortalTicketController::store() writes (Ticket::createNumbered,
     * department support, priority medium, first client reply, staff notified as for a portal-opened
     * ticket). The rate limit is shared with the hosting-support tickets (same marker), 3 per day.
     */
    private function createGeneralSupportTicket(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, string $text, string $lang): void
    {
        $description = trim(preg_replace('/[\x00-\x08\x0B\x0C\x0E-\x1F]/u', '', $text) ?? '');
        $len = mb_strlen($description);
        if ($len < self::SUPPORT_MIN || $len > self::SUPPORT_MAX) {
            $this->reply($tenant, $phone, $this->t($lang,
                'Samahani, ujumbe uwe kati ya herufi ' . self::SUPPORT_MIN . ' na ' . self::SUPPORT_MAX . " (sasa: {$len}). Jaribu tena.\n\n" . $this->menuFooter($lang),
                'Sorry, the message must be between ' . self::SUPPORT_MIN . ' and ' . self::SUPPORT_MAX . " characters (now: {$len}). Try again.\n\n" . $this->menuFooter($lang)
            ));
            return;
        }

        if ($this->whatsappTicketsLast24h($tenant, $client) >= self::WHATSAPP_TICKETS_PER_DAY) {
            Log::info('WhatsApp support request refused (daily limit)', ['tenant_id' => $tenant->id, 'client_id' => $client->id]);
            $this->finishFlow($tenant, $client, $phone, $this->supportLimitMessage($lang), $lang);
            return;
        }

        try {
            $ticket = \App\Models\Ticket::createNumbered([
                'tenant_id' => $tenant->id,
                'client_id' => $client->id,
                'subject' => 'WhatsApp support request',
                'department' => 'support',
                'status' => 'open',
                'priority' => 'medium',
                'last_reply_at' => now(),
            ]);
            $ticket->replies()->create([
                'tenant_id' => $tenant->id,
                'author_type' => 'client',
                'message' => self::TICKET_MARKER . ($session->assisted_by_user_id ? ' (created via staff-assist)' : '') . ".\n\n" . $description,
            ]);
        } catch (\Throwable $e) {
            Log::warning('WhatsApp support ticket failed', ['client_id' => $client->id, 'error' => $e->getMessage()]);
            $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, imeshindikana kutuma ujumbe. Tafadhali wasiliana nasi moja kwa moja.', "Sorry, we couldn't send the message. Please contact us directly."), $lang);
            return;
        }

        // Staff hear about it exactly as they do for a portal-opened ticket.
        try {
            foreach (\App\Http\Controllers\TicketController::staffToNotify($ticket) as $staff) {
                $staff->notify(new \App\Notifications\TicketActivityStaffNotification($ticket, 'opened'));
            }
        } catch (\Throwable $e) {
            Log::warning("Ticket staff notification failed for {$ticket->ticket_number}: {$e->getMessage()}");
        }

        $this->finishFlow($tenant, $client, $phone, $this->t($lang,
            "Asante, tumepokea ombi lako.\n• Tiketi namba: {$ticket->ticket_number}\nTutakujibu hivi karibuni.",
            "Thank you, we've received your request.\n• Ticket number: {$ticket->ticket_number}\nWe will get back to you shortly."
        ), $lang);
    }

    // ── My Servers ──

    /** The client's own active, linked, live servers (same rule as the portal's ownServer/index). */
    private function clientServers(Tenant $tenant, Client $client)
    {
        $subIds = \App\Models\ClientSubscription::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)->where('client_id', $client->id)
            ->where('status', 'active')->whereNull('deleted_at')->pluck('id');

        return \App\Models\LinodeResource::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)->where('client_id', $client->id)
            ->where('type', 'instance')->whereIn('client_subscription_id', $subIds)
            ->where(fn ($q) => $q->whereNull('status')->orWhere('status', '!=', 'gone'))
            ->orderBy('label');
    }

    private function serverLine(\App\Models\LinodeResource $s, string $lang): string
    {
        return "{$this->dot($s->status)} {$s->label} — IP " . ($s->ipv4[0] ?? '—') . " — {$s->region} — " . $this->serverStatusLabel($s->status, $lang);
    }

    private function startMyServers(Tenant $tenant, Client $client, string $phone, string $lang, ?string $query = null): void
    {
        $base = $this->clientServers($tenant, $client);
        if ($query !== null) {
            $base->where('label', 'like', '%' . addcslashes($query, '%_\\') . '%');
        }
        $total = (clone $base)->count();
        $servers = $base->limit(9)->get();

        if ($servers->isEmpty() && $query !== null) {
            $this->reply($tenant, $phone, $this->t($lang,
                "Hakuna server inayolingana na \"{$query}\". Jaribu jina lingine, au:\n\n" . $this->menuFooter($lang),
                "No server matches \"{$query}\". Try another name, or:\n\n" . $this->menuFooter($lang)
            ));
            return;
        }

        if ($servers->isEmpty()) {
            $this->finishFlow($tenant, $client, $phone, $this->t($lang,
                'Huna Cloud Server yoyote inayotumika kwetu kwa sasa.',
                "You don't have any active Cloud Servers with us right now."
            ), $lang);
            return;
        }

        if ($servers->count() === 1) {
            $this->showServer($tenant, $client, $phone, $servers->first(), $lang, multiple: false);
            return;
        }

        $lines = [];
        foreach ($servers as $i => $s) {
            $lines[] = ($i + 1) . ') ' . $this->serverLine($s, $lang);
        }

        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'flow' => 'my_servers', 'state' => ['step' => 'pick', 'server_ids' => $servers->pluck('id')->all(), 'capped' => $total > $servers->count()], 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(10)],
        );

        $this->reply($tenant, $phone, $this->t($lang,
            "*Server Zako*\n\n" . implode("\n", $lines) . $this->moreNotice($tenant, $lang, $total - $servers->count(), true) . "\n\n" . $this->menuFooter($lang),
            "*Your Cloud Servers*\n\n" . implode("\n", $lines) . $this->moreNotice($tenant, $lang, $total - $servers->count(), true) . "\n\n" . $this->menuFooter($lang)
        ));
    }

    private function showServer(Tenant $tenant, Client $client, string $phone, \App\Models\LinodeResource $srv, string $lang, bool $multiple): void
    {
        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'flow' => 'my_servers', 'state' => ['step' => 'detail', 'server_id' => $srv->id, 'multiple' => $multiple], 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(10)],
        );

        $this->reply($tenant, $phone, $this->t($lang,
            "*Cloud Server: {$srv->label}*\n• IP: " . ($srv->ipv4[0] ?? '—') . "\n• Eneo: {$srv->region}\n• Hali: {$this->dot($srv->status)} " . $this->serverStatusLabel($srv->status, 'sw') . "\n\n1) Anzisha upya (Reboot)\n\n" . $this->menuFooter($lang),
            "*Cloud Server: {$srv->label}*\n• IP: " . ($srv->ipv4[0] ?? '—') . "\n• Region: {$srv->region}\n• Status: {$this->dot($srv->status)} " . $this->serverStatusLabel($srv->status, 'en') . "\n\n1) Reboot\n\n" . $this->menuFooter($lang)
        ));
    }

    private function handleMyServersStep(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, string $text, string $lang): void
    {
        $state = $session->state ?? [];
        $step = $state['step'] ?? 'pick';
        $invalid = fn () => $this->invalidChoice($tenant, $phone, $lang, $step === 'pick' ? count($state['server_ids'] ?? []) : 1);

        if ($step === 'pick') {
            if ($this->isBackWord($text)) {
                $this->startMoreServices($tenant, $client, $phone, $lang);
                return;
            }
            if (!empty($state['capped']) && !preg_match('/^\s*\d+\s*$/', $text) && mb_strlen(trim($text)) >= 2) {
                $this->startMyServers($tenant, $client, $phone, $lang, trim($text));
                return;
            }
            if (!preg_match('/^\s*([1-9])\s*$/', $text, $m)) {
                $invalid();
                return;
            }
            $id = $state['server_ids'][(int) $m[1] - 1] ?? null;
            $srv = $id ? $this->clientServers($tenant, $client)->where('id', $id)->first() : null;
            if (!$srv) {
                $invalid();
                return;
            }
            $this->showServer($tenant, $client, $phone, $srv, $lang, multiple: count($state['server_ids']) > 1);
            return;
        }

        $srv = !empty($state['server_id']) ? $this->clientServers($tenant, $client)->where('id', $state['server_id'])->first() : null;
        if (!$srv) {
            $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, server hiyo haipatikani tena.', 'Sorry, that server is no longer available.'), $lang);
            return;
        }

        if ($step === 'detail') {
            if ($this->isBackWord($text)) {
                $state['multiple'] ?? false ? $this->startMyServers($tenant, $client, $phone, $lang) : $this->startMoreServices($tenant, $client, $phone, $lang);
                return;
            }
            if (!preg_match('/^\s*1\s*$/', $text)) {
                $invalid();
                return;
            }
            if ($session->assisted_by_user_id) {
                $this->auditServer($tenant, $client, $srv, 'whatsapp.server_reboot_refused', ['reason' => 'staff_assist'], 403, 'staff assist');
                $this->reply($tenant, $phone, $this->t($lang,
                    'Kwa usalama, kuanzisha upya server hakupatikani kwenye hali ya staff — mteja mwenyewe lazima aombe kutoka simu yake. Tafadhali tumia admin panel.',
                    'For security, rebooting a server is not available in staff-assist mode — the client must request it from their own phone. Please use the admin panel.'
                ));
                return;
            }
            $session->update(['state' => ['step' => 'confirm_name', 'server_id' => $srv->id, 'multiple' => $state['multiple'] ?? false], 'expires_at' => now()->addMinutes(10)]);
            $this->reply($tenant, $phone, $this->t($lang,
                "Kuthibitisha, andika jina kamili la server: {$srv->label}\n(Server itazimika kwa muda mfupi.) Andika 0 kughairi.",
                "To confirm, type the exact server name: {$srv->label}\n(The server will be briefly unavailable.) Type 0 to cancel."
            ));
            return;
        }

        if ($step === 'confirm_name') {
            if ($this->isBackWord($text)) {
                $this->showServer($tenant, $client, $phone, $srv, $lang, multiple: (bool) ($state['multiple'] ?? false));
                return;
            }
            $this->rebootServer($tenant, $client, $phone, $session, $srv, $text, $lang);
            return;
        }

        $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, kuna hitilafu. Tafadhali jaribu tena.', 'Sorry, something went wrong. Please try again.'), $lang);
    }

    private function auditServer(Tenant $tenant, Client $client, \App\Models\LinodeResource $srv, string $action, array $extra = [], int $status = 200, ?string $error = null): void
    {
        \App\Models\LinodeAuditLog::withoutGlobalScopes()->create([
            'tenant_id' => $tenant->id, 'user_id' => null, 'linode_account_id' => $srv->linode_account_id,
            'action' => $action, 'target' => "{$srv->label} #{$srv->remote_id}",
            'request' => ['server_id' => $srv->id, 'server_label' => $srv->label, 'client_id' => $client->id, 'channel' => 'whatsapp'] + $extra,
            'response_status' => $status, 'error' => $error ? mb_substr($error, 0, 250) : null,
        ]);
    }

    /** Mirrors PortalLinodeController::reboot() (same checks, limits and shared counters); the only server action clients get. */
    private function rebootServer(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, \App\Models\LinodeResource $srv, string $typed, string $lang): void
    {
        $refuse = function (string $sw, string $en, int $code, string $why, bool $finish = false) use ($tenant, $client, $phone, $srv, $lang) {
            $this->auditServer($tenant, $client, $srv, 'whatsapp.server_reboot_refused', ['reason' => $why], $code, $why);
            $msg = $this->t($lang, $sw, $en);
            $finish ? $this->finishFlow($tenant, $client, $phone, $msg, $lang) : $this->reply($tenant, $phone, $msg);
        };

        if ($session->assisted_by_user_id) {
            $refuse('Kuanzisha upya server hakupatikani kwenye hali ya staff.', 'Rebooting a server is not available in staff-assist mode.', 403, 'staff_assist', true);
            return;
        }

        $account = \App\Models\LinodeAccount::withoutGlobalScopes()->where('id', $srv->linode_account_id)->where('tenant_id', $tenant->id)->first();
        if (!$account || $account->status !== 'active') {
            $refuse('Kuanzisha upya hakupatikani kwa server hii sasa. Tafadhali wasiliana nasi.', 'Reboot is not available for this server right now. Please contact us.', 422, 'account_inactive', true);
            return;
        }
        if ($typed !== $srv->label) {
            $refuse("Jina halilingani. Andika jina kamili la server: {$srv->label} (au 0 kughairi).", "That doesn't match. Type the exact server name: {$srv->label} (or 0 to cancel).", 422, 'wrong_confirm');
            return;
        }

        $target = "{$srv->label} #{$srv->remote_id}";
        $actions = ['portal.server_reboot', 'whatsapp.server_reboot', 'server.power'];
        $hour = \App\Models\LinodeAuditLog::withoutGlobalScopes()->where('tenant_id', $tenant->id)->where('created_at', '>=', now()->subHour());
        if ((clone $hour)->where('linode_account_id', $account->id)->where('target', $target)->whereIn('action', $actions)->count() >= self::SERVER_REBOOT_PER_SERVER_HOUR) {
            $refuse('Kikomo kimefikiwa: server inaweza kuanzishwa upya mara ' . self::SERVER_REBOOT_PER_SERVER_HOUR . ' tu kwa saa. Jaribu tena baadaye.', 'Limit reached: at most ' . self::SERVER_REBOOT_PER_SERVER_HOUR . ' reboots per server per hour. Please try again later.', 429, 'server_hour_limit', true);
            return;
        }
        $day = \App\Models\LinodeAuditLog::withoutGlobalScopes()->where('tenant_id', $tenant->id)->whereIn('action', ['portal.server_reboot', 'whatsapp.server_reboot'])
            ->where('created_at', '>=', now()->subDay())->where('request->client_id', $client->id);
        if ($day->count() >= self::SERVER_REBOOT_PER_CLIENT_DAY) {
            $refuse('Kikomo kimefikiwa: mara ' . self::SERVER_REBOOT_PER_CLIENT_DAY . ' tu kwa siku. Tafadhali wasiliana nasi.', 'Limit reached: at most ' . self::SERVER_REBOOT_PER_CLIENT_DAY . ' reboots per day. Please contact us.', 429, 'client_day_limit', true);
            return;
        }
        if ((clone $hour)->whereIn('action', $actions)->count() >= self::SERVER_REBOOT_PER_TENANT_HOUR) {
            $refuse('Maombi ni mengi sasa hivi. Tafadhali jaribu tena baadaye.', 'Too many server actions right now. Please try again later.', 429, 'tenant_hour_limit', true);
            return;
        }

        try {
            $before = (new \App\Services\Linode\LinodeService($account))->powerAction($srv->remote_id, 'reboot');
        } catch (\DomainException $e) {
            // Live status is not "running" (offline/busy) — nothing was sent.
            $refuse('Server haiwezi kuanzishwa upya sasa hivi — lazima iwe inafanya kazi. Jaribu tena baada ya muda.', "The server can't be rebooted right now — it must be running. Please try again in a minute.", 409, 'not_running', true);
            return;
        } catch (\Throwable $e) {
            Log::warning('WhatsApp server reboot failed', ['server_id' => $srv->id, 'error' => $e->getMessage()]);
            $this->auditServer($tenant, $client, $srv, 'whatsapp.server_reboot', ['result' => 'failed'], 502, $e->getMessage());
            $this->finishFlow($tenant, $client, $phone, $this->t($lang,
                'Kuanzisha upya kumeshindikana. Tafadhali jaribu tena baada ya dakika moja au wasiliana nasi.',
                'The reboot could not be started. Please try again in a minute or contact us.'
            ), $lang);
            return;
        }

        $srv->status = \App\Services\Linode\LinodeService::POWER_OPTIMISTIC['reboot'];
        $srv->save();
        $this->auditServer($tenant, $client, $srv, 'whatsapp.server_reboot', ['result' => 'success', 'status_before' => $before]);

        $this->finishFlow($tenant, $client, $phone, $this->t($lang,
            "Server {$srv->label} inaanzishwa upya. Kwa kawaida huchukua dakika 1-2.",
            "Reboot started for {$srv->label}. It usually takes 1-2 minutes."
        ), $lang);
    }

    // ── Expiring soon ──

    /** Renewal price for a domain, resolved exactly like DomainBillingService::createRenewalInvoice(). */
    private function domainRenewPrice(Domain $domain): ?float
    {
        $tld = strtolower(explode('.', $domain->name, 2)[1] ?? '');
        $pricing = DomainTld::priceFor($domain->tenant_id, $tld);
        if (!$pricing && ($domain->meta['registrar'] ?? null) === 'namecom') {
            $pricing = DomainTld::where('tenant_id', $domain->tenant_id)->where('registrar', 'namecom')->where('tld', $tld)->where('renew_price', '>', 0)->first();
        }
        return $pricing ? (float) $pricing->renew_price : null;
    }

    /** Domains, hosting and Cloud Servers expiring in the next 60 days or lapsed in the last 30, soonest first (all of them; callers cap at EXPIRING_MAX). */
    private function expiringItems(Tenant $tenant, Client $client): array
    {
        $from = now()->subDays(self::EXPIRING_BEHIND_DAYS)->startOfDay();
        $to = now()->addDays(self::EXPIRING_AHEAD_DAYS)->endOfDay();
        $items = [];

        $ownDomainNames = Domain::withoutGlobalScopes()->where('tenant_id', $tenant->id)->where('client_id', $client->id)
            ->whereNotIn('status', ['cancelled', 'transferred_out'])->pluck('name')->all();

        $domains = Domain::withoutGlobalScopes()->where('tenant_id', $tenant->id)->where('client_id', $client->id)
            ->whereIn('status', ['active', 'expired'])->whereNotNull('expires_at')
            ->whereBetween('expires_at', [$from, $to])->get();
        foreach ($domains as $d) {
            $items[] = ['kind' => 'domain', 'id' => $d->id, 'name' => $d->name, 'type' => 'Domain', 'expires' => $d->expires_at, 'price' => $this->domainRenewPrice($d)];
        }

        $subs = \App\Models\ClientSubscription::withoutGlobalScopes()->where('tenant_id', $tenant->id)->where('client_id', $client->id)
            ->whereNull('deleted_at')->whereIn('status', ['active', 'expired'])->whereNotNull('expire_date')
            ->whereBetween('expire_date', [$from, $to])
            ->with(['productService' => fn ($q) => $q->withoutGlobalScopes()])->get();
        $subIds = $subs->pluck('id');
        $servers = \App\Models\LinodeResource::withoutGlobalScopes()->where('tenant_id', $tenant->id)->where('client_id', $client->id)
            ->whereIn('client_subscription_id', $subIds)->get()->keyBy('client_subscription_id');
        $hostings = HostingAccount::withoutGlobalScopes()->where('tenant_id', $tenant->id)
            ->whereIn('client_subscription_id', $subIds)->get()->keyBy('client_subscription_id');

        foreach ($subs as $sub) {
            $category = (string) ($sub->productService?->category ?? '');
            if ($category === 'Domain' && in_array($sub->label, $ownDomainNames, true)) {
                continue; // already listed through the Domain record itself
            }
            $server = $servers->get($sub->id);
            $hosting = $hostings->get($sub->id);
            [$type, $name] = match (true) {
                (bool) $server => ['Cloud Server', $server->label],
                (bool) $hosting => ['Hosting', $hosting->domain],
                $category === 'Domain' => ['Domain', $sub->label ?: ($sub->productService?->name ?? 'Domain')],
                default => [$category !== '' ? $category : 'Service', $sub->label ?: ($sub->productService?->name ?? 'Service')],
            };
            try {
                $price = (float) app(\App\Services\RecurringInvoiceService::class)->previewForSubscriptions([$sub])['total'];
            } catch (\Throwable $e) {
                $price = null;
            }
            $items[] = ['kind' => 'sub', 'id' => $sub->id, 'name' => $name, 'type' => $type, 'expires' => $sub->expire_date, 'price' => $price];
        }

        usort($items, fn ($a, $b) => $a['expires']->getTimestamp() <=> $b['expires']->getTimestamp());

        return $items;
    }

    /** Whole days from today to $date (negative when already past). */
    private function daysUntil(\Carbon\CarbonInterface $date): int
    {
        return (int) now()->startOfDay()->diffInDays($date->copy()->startOfDay(), false);
    }

    /** The one place "12 days left / expires today / expired 3 days ago" is worded (Expiring soon, My Domains, My Hosting). */
    private function expiryPhrase(int $days, string $lang): string
    {
        $sw = $lang === 'sw';
        return match (true) {
            $days > 0 => $sw ? "siku {$days} zimebaki" : "{$days} days left",
            $days === 0 => $sw ? 'inaisha leo' : 'expires today',
            default => $sw ? 'imeisha siku ' . abs($days) . ' zilizopita' : 'expired ' . abs($days) . ' days ago',
        };
    }

    /** Status emoji for a dated service: 🔴 stopped, ⚠️ expired or due within 7 days, else the plain status dot. */
    private function serviceEmoji(?string $status, ?int $days): string
    {
        if (in_array($status, ['suspended', 'failed', 'cancelled'], true)) {
            return '🔴';
        }
        if ($status === 'expired' || ($days !== null && $days <= 7)) {
            return '⚠️';
        }
        return $this->dot($status);
    }

    private function startExpiring(Tenant $tenant, Client $client, string $phone, string $lang, ?string $query = null): void
    {
        $all = $this->expiringItems($tenant, $client);
        if ($query !== null) {
            $all = array_values(array_filter($all, fn ($it) => mb_stripos($it['name'], $query) !== false));
            if (!$all) {
                $this->reply($tenant, $phone, $this->t($lang,
                    "Hakuna kinachokaribia kuisha kinacholingana na \"{$query}\". Jaribu jina lingine, au:\n\n" . $this->menuFooter($lang),
                    "Nothing expiring matches \"{$query}\". Try another name, or:\n\n" . $this->menuFooter($lang)
                ));
                return;
            }
        }
        $items = array_slice($all, 0, self::EXPIRING_MAX);

        if (!$items) {
            $this->finishFlow($tenant, $client, $phone, $this->t($lang,
                'Hakuna huduma inayokaribia kuisha (siku 60 zijazo) wala iliyoisha hivi karibuni. Asante!',
                'Nothing is expiring in the next 60 days or lapsed recently. Thank you!'
            ), $lang);
            return;
        }

        $sw = $lang === 'sw';
        $lines = [];
        foreach ($items as $i => $it) {
            $days = $this->daysUntil($it['expires']);
            $when = $this->expiryPhrase($days, $lang);
            $price = $it['price'] !== null ? 'TZS ' . number_format($it['price']) : ($sw ? 'bei: wasiliana nasi' : 'price: contact us');
            $warn = $days <= 7 ? '⚠️ ' : '';
            $lines[] = ($i + 1) . ") {$warn}{$it['name']} — {$it['type']} — " . $it['expires']->format('d M Y') . " ({$when}) — {$price}";
        }

        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'flow' => 'expiring', 'state' => ['step' => 'pick', 'capped' => count($all) > count($items), 'items' => array_map(fn ($it) => ['kind' => $it['kind'], 'id' => $it['id']], $items)], 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(15)],
        );

        $this->reply($tenant, $phone, $this->t($lang,
            "*Zinazokaribia kuisha*\n\n" . implode("\n", $lines) . $this->moreNotice($tenant, $lang, count($all) - count($items), true) . "\n\nJibu na namba kulipia/kuhuisha huduma hiyo.\n\n" . $this->menuFooter($lang),
            "*Expiring soon*\n\n" . implode("\n", $lines) . $this->moreNotice($tenant, $lang, count($all) - count($items), true) . "\n\nReply with a number to renew and pay for that service.\n\n" . $this->menuFooter($lang)
        ));
    }

    private function handleExpiringStep(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, string $text, string $lang): void
    {
        if ($this->isBackWord($text)) {
            $this->startMoreServices($tenant, $client, $phone, $lang);
            return;
        }

        $state = $session->state ?? [];
        $entry = null;
        if (preg_match('/^\s*(\d{1,2})\s*$/', $text, $m)) {
            $entry = $state['items'][(int) $m[1] - 1] ?? null;
        } elseif (!empty($state['capped']) && mb_strlen(trim($text)) >= 2) {
            $this->startExpiring($tenant, $client, $phone, $lang, trim($text));
            return;
        }
        if (!$entry) {
            $this->invalidChoice($tenant, $phone, $lang, count($state['items'] ?? []));
            return;
        }

        $this->renewAndOffer($tenant, $client, $phone, $lang, $entry['kind'], $entry['id']);
    }

    /**
     * Renewal invoice for a domain ('domain') or a subscription/hosting/server ('sub') — an already-open
     * renewal invoice is reused, never duplicated — then straight into the payment-method choice.
     * Shared by Expiring soon, My Domains and My Hosting.
     */
    private function renewAndOffer(Tenant $tenant, Client $client, string $phone, string $lang, string $kind, string $id): void
    {
        try {
            $document = $kind === 'domain'
                ? $this->renewalInvoiceForDomain($tenant, $client, $id)
                : $this->renewalInvoiceForSubscription($tenant, $client, $id);
        } catch (\Throwable $e) {
            Log::warning('WhatsApp renewal failed', ['kind' => $kind, 'id' => $id, 'error' => $e->getMessage()]);
            $this->finishFlow($tenant, $client, $phone, $this->t($lang,
                'Samahani, hatuwezi kutengeneza invoice ya huduma hii sasa hivi. Tafadhali wasiliana nasi.',
                "Sorry, we can't create the invoice for this service right now. Please contact us."
            ), $lang);
            return;
        }

        if (!$document) {
            $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, huduma hiyo haipatikani tena.', 'Sorry, that service is no longer available.'), $lang);
            return;
        }

        $this->offerPayment($tenant, $client, $phone, $document, $lang);
    }

    // ── 11) My Domains ──

    private function setSimpleState(Tenant $tenant, Client $client, string $phone, string $flow, array $state): void
    {
        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'flow' => $flow, 'state' => $state, 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(10)],
        );
    }

    private function startMyDomains(Tenant $tenant, Client $client, string $phone, string $lang, ?string $query = null): void
    {
        $base = Domain::withoutGlobalScopes()->where('tenant_id', $tenant->id)->where('client_id', $client->id)
            ->whereIn('status', ['active', 'expired'])
            ->orderByRaw('expires_at IS NULL')->orderBy('expires_at')->orderBy('name');
        if ($query !== null) {
            $base->where('name', 'like', '%' . addcslashes($query, '%_\\') . '%');
        }
        $total = (clone $base)->count();
        $domains = $base->limit(9)->get();

        if ($domains->isEmpty()) {
            $msg = $query !== null
                ? $this->t($lang, "Hakuna domain inayolingana na \"{$query}\". Jaribu jina lingine, au:\n\n" . $this->menuFooter($lang), "No domain matches \"{$query}\". Try another name, or:\n\n" . $this->menuFooter($lang))
                : null;
            if ($msg) {
                $this->reply($tenant, $phone, $msg);
            } else {
                $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Huna domain iliyosajiliwa kwa sasa.', "You don't have any registered domains right now."), $lang);
            }
            return;
        }

        $sw = $lang === 'sw';
        $lines = [];
        foreach ($domains as $i => $d) {
            if ($d->expires_at) {
                $days = $this->daysUntil($d->expires_at);
                $when = ($sw ? 'inaisha ' : 'expires ') . $d->expires_at->format('d M Y') . ' (' . $this->expiryPhrase($days, $lang) . ')';
            } else {
                $days = null;
                $when = $sw ? 'tarehe haipatikani' : 'no expiry date';
            }
            $lines[] = ($i + 1) . ") {$d->name} — {$when} — " . $this->serviceEmoji($d->status, $days);
        }

        $this->setSimpleState($tenant, $client, $phone, 'my_domains', ['step' => 'pick', 'capped' => $total > $domains->count(), 'ids' => $domains->pluck('id')->all()]);
        $notice = $this->moreNotice($tenant, $lang, $total - $domains->count(), true);
        $this->reply($tenant, $phone, $this->t($lang,
            "*Domain Zangu*\n\n" . implode("\n", $lines) . $notice . "\n\nJibu na namba kuona maelezo.\n\n" . $this->menuFooter($lang),
            "*My Domains*\n\n" . implode("\n", $lines) . $notice . "\n\nReply with a number for details.\n\n" . $this->menuFooter($lang)
        ));
    }

    /** Renewable through us: we hold a renewal price for the TLD, and it is not registered/managed elsewhere. */
    private function domainRenewable(Domain $d): bool
    {
        if (!in_array($d->status, ['active', 'expired'], true) || $this->domainRenewPrice($d) === null) {
            return false;
        }
        return !($d->meta['unmanaged'] ?? false) || ($d->meta['registrar'] ?? null) === 'namecom';
    }

    private function handleMyDomainsStep(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, string $text, string $lang): void
    {
        $state = $session->state ?? [];
        $step = $state['step'] ?? 'pick';

        if ($step === 'pick') {
            if ($this->isBackWord($text)) {
                $this->sendRootMenu($tenant, $client, $phone, $lang);
                return;
            }
            if (!empty($state['capped']) && !preg_match('/^\s*\d+\s*$/', $text) && mb_strlen(trim($text)) >= 2) {
                $this->startMyDomains($tenant, $client, $phone, $lang, trim($text));
                return;
            }
            $id = preg_match('/^\s*([1-9])\s*$/', $text, $m) ? ($state['ids'][(int) $m[1] - 1] ?? null) : null;
            $domain = $id ? Domain::withoutGlobalScopes()->where('tenant_id', $tenant->id)->where('client_id', $client->id)->whereIn('status', ['active', 'expired'])->find($id) : null;
            if (!$domain) {
                $this->invalidChoice($tenant, $phone, $lang, count($state['ids'] ?? []));
                return;
            }
            $this->showMyDomain($tenant, $client, $phone, $domain, $lang);
            return;
        }

        // detail
        $domain = !empty($state['domain_id'])
            ? Domain::withoutGlobalScopes()->where('tenant_id', $tenant->id)->where('client_id', $client->id)->whereIn('status', ['active', 'expired'])->find($state['domain_id'])
            : null;
        if (!$domain) {
            $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, domain hiyo haipatikani tena.', 'Sorry, that domain is no longer available.'), $lang);
            return;
        }
        if ($this->isBackWord($text)) {
            $this->startMyDomains($tenant, $client, $phone, $lang);
            return;
        }
        $renewable = $this->domainRenewable($domain);
        if ($renewable && preg_match('/^\s*1\s*$/', $text)) {
            $this->renewAndOffer($tenant, $client, $phone, $lang, 'domain', $domain->id);
            return;
        }
        $this->invalidChoice($tenant, $phone, $lang, $renewable ? 1 : 0);
    }

    private function showMyDomain(Tenant $tenant, Client $client, string $phone, Domain $d, string $lang): void
    {
        $sw = $lang === 'sw';
        $days = $d->expires_at ? $this->daysUntil($d->expires_at) : null;
        $renewable = $this->domainRenewable($d);
        $price = $this->domainRenewPrice($d);
        $auto = $d->auto_renew || (bool) ($d->meta['manual_auto_renew_requested'] ?? false);

        $lines = ["*{$d->name}*"];
        $lines[] = ($sw ? '• Inaisha: ' : '• Expires: ') . ($d->expires_at ? $d->expires_at->format('d M Y') . ' (' . $this->expiryPhrase($days, $lang) . ')' : '—');
        $lines[] = ($sw ? '• Hali: ' : '• Status: ') . $this->serviceEmoji($d->status, $days) . ' ' . $this->statusLabel($d->status, $lang);
        $lines[] = ($sw ? '• Kuhuisha otomatiki: ' : '• Auto-renew: ') . ($auto ? ($sw ? 'Imewashwa' : 'On') : ($sw ? 'Imezimwa' : 'Off'));
        if ($price !== null) {
            $lines[] = ($sw ? '• Bei ya kuhuisha (mwaka 1): TZS ' : '• Renewal price (1 year): TZS ') . number_format($price);
        }
        $lines[] = '';
        if ($renewable) {
            $lines[] = $sw ? '1) Huisha' : '1) Renew';
            $lines[] = '';
        } else {
            $lines[] = $sw ? 'Wasiliana nasi kuhuisha domain hii.' : 'Contact us to renew this domain.';
            $lines[] = '';
        }
        $lines[] = $this->menuFooter($lang);

        $this->setSimpleState($tenant, $client, $phone, 'my_domains', ['step' => 'detail', 'domain_id' => $d->id]);
        $this->reply($tenant, $phone, implode("\n", $lines));
    }

    // ── 12) My Hosting ──

    private function startMyHosting(Tenant $tenant, Client $client, string $phone, string $lang, ?string $query = null): void
    {
        // Soonest expiry first (same order as My Domains), name as the tie-break.
        $base = $this->clientHostingAccounts($tenant, $client)->whereIn('hosting_accounts.status', ['active', 'suspended'])
            ->reorder()
            ->orderByRaw('(select expire_date from client_subscriptions where client_subscriptions.id = hosting_accounts.client_subscription_id) is null')
            ->orderBy(\App\Models\ClientSubscription::withoutGlobalScopes()->select('expire_date')->whereColumn('client_subscriptions.id', 'hosting_accounts.client_subscription_id'))
            ->orderBy('hosting_accounts.domain');
        if ($query !== null) {
            $base->where('hosting_accounts.domain', 'like', '%' . addcslashes($query, '%_\\') . '%');
        }
        $total = (clone $base)->count();
        $accounts = $base->limit(9)->get();

        if ($accounts->isEmpty()) {
            if ($query !== null) {
                $this->reply($tenant, $phone, $this->t($lang,
                    "Hakuna hosting inayolingana na \"{$query}\". Jaribu jina lingine, au:\n\n" . $this->menuFooter($lang),
                    "No hosting matches \"{$query}\". Try another name, or:\n\n" . $this->menuFooter($lang)
                ));
            } else {
                $this->finishFlow($tenant, $client, $phone, $this->t($lang,
                    'Huna hosting yoyote iliyosajiliwa kwetu kwa sasa. Chagua 3 kisha 1 kuagiza hosting mpya.',
                    "You don't have any hosting registered with us yet. Choose 3 then 1 to order new hosting."
                ), $lang);
            }
            return;
        }

        $sw = $lang === 'sw';
        $lines = [];
        foreach ($accounts as $i => $a) {
            $sub = $a->subscription;
            $plan = $this->hostingPlanName($tenant, $a);
            $exp = $sub?->expire_date;
            $days = $exp ? $this->daysUntil($exp) : null;
            $when = $exp ? ($sw ? 'inaisha ' : 'expires ') . $exp->format('d M Y') . ' (' . $this->expiryPhrase($days, $lang) . ')' : ($sw ? 'tarehe haipatikani' : 'no expiry date');
            $lines[] = ($i + 1) . ") {$a->domain} — {$plan} — {$when} — " . $this->serviceEmoji($a->status, $days);
        }

        $this->setSimpleState($tenant, $client, $phone, 'my_hosting', ['step' => 'pick', 'capped' => $total > $accounts->count(), 'ids' => $accounts->pluck('id')->all()]);
        $notice = $this->moreNotice($tenant, $lang, $total - $accounts->count(), true);
        $this->reply($tenant, $phone, $this->t($lang,
            "*Hosting Yangu*\n\n" . implode("\n", $lines) . $notice . "\n\nJibu na namba kuona maelezo.\n\n" . $this->menuFooter($lang),
            "*My Hosting*\n\n" . implode("\n", $lines) . $notice . "\n\nReply with a number for details.\n\n" . $this->menuFooter($lang)
        ));
    }

    private function hostingPlanName(Tenant $tenant, HostingAccount $a): string
    {
        if ($a->package) {
            return (string) $a->package;
        }
        $ps = $a->subscription ? ProductService::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($a->subscription->product_service_id) : null;
        return $ps?->name ?? ($a->meta['plan'] ?? '—');
    }

    private function myHostingAccount(Tenant $tenant, Client $client, ?string $id): ?HostingAccount
    {
        return $id ? $this->clientHostingAccounts($tenant, $client)->whereIn('hosting_accounts.status', ['active', 'suspended'])->where('hosting_accounts.id', $id)->first() : null;
    }

    private function handleMyHostingStep(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, string $text, string $lang): void
    {
        $state = $session->state ?? [];
        $step = $state['step'] ?? 'pick';

        if ($step === 'pick') {
            if ($this->isBackWord($text)) {
                $this->sendRootMenu($tenant, $client, $phone, $lang);
                return;
            }
            if (!empty($state['capped']) && !preg_match('/^\s*\d+\s*$/', $text) && mb_strlen(trim($text)) >= 2) {
                $this->startMyHosting($tenant, $client, $phone, $lang, trim($text));
                return;
            }
            $id = preg_match('/^\s*([1-9])\s*$/', $text, $m) ? ($state['ids'][(int) $m[1] - 1] ?? null) : null;
            $account = $this->myHostingAccount($tenant, $client, $id);
            if (!$account) {
                $this->invalidChoice($tenant, $phone, $lang, count($state['ids'] ?? []));
                return;
            }
            $this->showMyHosting($tenant, $client, $phone, $account, $lang);
            return;
        }

        $account = $this->myHostingAccount($tenant, $client, $state['account_id'] ?? null);
        if (!$account) {
            $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, akaunti hiyo haipatikani tena.', 'Sorry, that account is no longer available.'), $lang);
            return;
        }
        if ($this->isBackWord($text)) {
            $this->startMyHosting($tenant, $client, $phone, $lang);
            return;
        }
        $option = preg_match('/^\s*([1-9])\s*$/', $text, $m) ? ($state['options'][(int) $m[1] - 1] ?? null) : null;
        if ($option === 'renew' && $account->subscription) {
            $this->renewAndOffer($tenant, $client, $phone, $lang, 'sub', $account->subscription->id);
        } elseif ($option === 'manage') {
            // Hand over to the EXISTING hosting_manage flow for this account (cPanel, email, upgrade, support...).
            $this->showHostingAccount($tenant, $client, $phone, $account, $lang, multiple: false);
        } else {
            $this->invalidChoice($tenant, $phone, $lang, count($state['options'] ?? []));
        }
    }

    private function showMyHosting(Tenant $tenant, Client $client, string $phone, HostingAccount $a, string $lang): void
    {
        $sw = $lang === 'sw';
        $sub = $a->subscription;
        $exp = $sub?->expire_date;
        $days = $exp ? $this->daysUntil($exp) : null;

        $lines = ["*Hosting: {$a->domain}*"];
        $lines[] = ($sw ? '• Kifurushi: ' : '• Plan: ') . $this->hostingPlanName($tenant, $a);
        $lines[] = '• Domain: ' . $a->domain;
        $lines[] = ($sw ? '• Inaisha: ' : '• Expires: ') . ($exp ? $exp->format('d M Y') . ' (' . $this->expiryPhrase($days, $lang) . ')' : '—');
        $lines[] = ($sw ? '• Hali: ' : '• Status: ') . $this->serviceEmoji($a->status, $days) . ' ' . $this->hostingStatusLabel($a->status, $lang);

        $options = [];
        $opts = [];
        if ($sub && in_array($sub->status, ['active', 'expired'], true)) {
            $options[] = 'renew';
            $opts[] = count($options) . ($sw ? ') Huisha' : ') Renew');
        }
        $options[] = 'manage';
        $opts[] = count($options) . ($sw ? ') Simamia hosting' : ') Manage hosting');

        $this->setSimpleState($tenant, $client, $phone, 'my_hosting', ['step' => 'detail', 'account_id' => $a->id, 'options' => $options]);
        $this->reply($tenant, $phone, implode("\n", $lines) . "\n\n" . implode("\n", $opts) . "\n\n" . $this->menuFooter($lang));
    }

    private function openInvoice(Tenant $tenant, Client $client, ?string $documentId): ?Document
    {
        if (!$documentId) {
            return null;
        }
        $doc = Document::withoutGlobalScopes()->where('tenant_id', $tenant->id)->where('client_id', $client->id)
            ->where('type', 'invoice')->whereIn('status', ['sent', 'overdue', 'partial'])->find($documentId);

        return $doc && $doc->balance_due > 0 ? $doc : null;
    }

    /** Same invoice the portal's "Renew" makes (DomainBillingService); an already-open renewal invoice is reused, never duplicated. */
    private function renewalInvoiceForDomain(Tenant $tenant, Client $client, string $domainId): ?Document
    {
        $domain = Domain::withoutGlobalScopes()->where('tenant_id', $tenant->id)->where('client_id', $client->id)
            ->whereIn('status', ['active', 'expired'])->find($domainId);
        if (!$domain) {
            return null;
        }

        return $this->openInvoice($tenant, $client, $domain->meta['renewal_document_id'] ?? null)
            ?? app(\App\Services\Registrar\DomainBillingService::class)->createRenewalInvoice($domain, 1);
    }

    /** Hosting / Cloud Server / other subscription: reuse its open invoice, else the same generator staff's "Generate invoice" uses. */
    private function renewalInvoiceForSubscription(Tenant $tenant, Client $client, string $subId): ?Document
    {
        $sub = \App\Models\ClientSubscription::withoutGlobalScopes()->where('tenant_id', $tenant->id)->where('client_id', $client->id)
            ->whereNull('deleted_at')->whereIn('status', ['active', 'expired'])
            ->with(['productService' => fn ($q) => $q->withoutGlobalScopes()])->find($subId);
        if (!$sub) {
            return null;
        }

        $docIds = \App\Models\RecurringInvoiceLog::withoutGlobalScopes()->where('tenant_id', $tenant->id)->where('client_id', $client->id)
            ->where('client_subscription_id', $sub->id)->whereNotNull('document_id')->pluck('document_id');
        if ($docIds->isNotEmpty()) {
            $open = Document::withoutGlobalScopes()->where('tenant_id', $tenant->id)->where('client_id', $client->id)
                ->where('type', 'invoice')->whereIn('id', $docIds)->whereIn('status', ['sent', 'overdue', 'partial'])
                ->orderBy('due_date')->get()->first(fn ($d) => $d->balance_due > 0);
            if ($open) {
                return $open;
            }
        }

        return app(\App\Services\RecurringInvoiceService::class)->generateForSubscriptions([$sub]);
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
        $this->setHostingState($tenant, $client, $phone, ['step' => 'email_menu', 'account_id' => $account->id, 'options' => ['create', 'forgot'], 'account_ids' => [$account->id]]);
        $this->reply($tenant, $phone, $this->t($lang,
            "*Email zangu: {$account->domain}*\n\n1) Tengeneza email mpya (jina@{$account->domain})\n2) Nimesahau password ya email\n\n" . $this->menuFooter($lang),
            "*My email accounts: {$account->domain}*\n\n1) Create a new email (name@{$account->domain})\n2) I forgot my email password\n\n" . $this->menuFooter($lang)
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
                'Samahani, jina hilo si sahihi. Tumia herufi ndogo, namba, . _ - tu (hadi 32), bila @ na bila nafasi. Jaribu tena, au 0 kurudi.',
                'Sorry, that name is not valid. Use lowercase letters, numbers, . _ - only (up to 32), with no @ and no spaces. Try again, or 0 to go back.'
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
            $lines[] = '';
            $lines[] = $sw ? 'Unataka tubadilishe nameservers?' : 'Change the nameservers now?';
            $lines[] = $this->yesNoOptions($lang);
            $this->reply($tenant, $phone, implode("\n", $lines));
            return;
        }

        $lines[] = $sw
            ? '• Domain hii haijasajiliwa nasi: weka nameservers hizi (au A record) kwenye mtoa huduma wa domain yako. Hatuwezi kubadilisha kwa niaba yako.'
            : '• This domain is not registered with us: set these nameservers (or the A record) at your domain registrar. We cannot change them for you.';
        $lines[] = '';
        $lines[] = $this->menuFooter($lang);
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
            "Eleza tatizo au ombi lako kuhusu {$account->domain} kwa ujumbe mmoja (hadi herufi 500).\n\n" . $this->menuFooter($lang),
            "Describe your issue or request about {$account->domain} in one message (up to 500 characters).\n\n" . $this->menuFooter($lang)
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
            $ticket = \App\Models\Ticket::createNumbered([
                'tenant_id' => $tenant->id,
                'client_id' => $client->id,
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
        $moreDue = 0;

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

            if (!empty($billable) && count($items) >= 9) {
                $moreDue++; // capped: reported in the "more" notice, never mislabelled as "nothing due"
                continue;
            }

            if (!empty($billable)) {
                $items[] = $domain->id;
                $what = implode(' + ', array_unique(array_map(fn ($s) => $s->productService->category, $billable)));
                // The subscription's own due date (why it's flagged), not the domain
                // registry's expiry — the two frequently disagree (WHMCS-import
                // artifacts), and showing the domain's date here has read as a
                // contradiction ("needs payment" next to an expiry a year out).
                $dueDate = collect($billable)->pluck('expire_date')->filter()->min()?->format('d M Y') ?? '—';
                $lines[] = count($items) . ") ⚠️ {$domain->name} — {$what} " . $this->t($lang, "inahitaji malipo (deadline {$dueDate})", "payment due (deadline {$dueDate})");
            } else {
                $expires = $domain->expires_at?->format('d M Y') ?? '—';
                $lines[] = $this->dot($domain->status) . " {$domain->name} — " . $this->t($lang, "inaisha {$expires}, hakuna malipo yanayohitajika sasa", "expires {$expires}, nothing due right now");
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
            "Habari {$client->name}, *huduma zako*\n\n" . implode("\n", $lines) . $this->moreNotice($tenant, $lang, $moreDue, false)
                . (!empty($items) ? "\n\nJibu na namba kulipia huduma inayohitaji malipo.\n\n" . $this->menuFooter($lang) : "\n\n" . $this->menuFooter($lang, false)),
            "Hi {$client->name}, *your services*\n\n" . implode("\n", $lines) . $this->moreNotice($tenant, $lang, $moreDue, false)
                . (!empty($items) ? "\n\nReply with a number to pay for a due service.\n\n" . $this->menuFooter($lang) : "\n\n" . $this->menuFooter($lang, false))
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

        $account = $hostingAccount ?? new HostingAccount([
            'tenant_id' => $tenant->id,
            'domain' => $domain->name,
        ]);

        try {
            $document = $bundler->generate($account, selfService: true);
        } catch (\Throwable $e) {
            Log::warning('WhatsApp renewal invoice generation failed', ['tenant_id' => $tenant->id, 'phone' => $phone, 'domain' => $domain->name, 'error' => $e->getMessage()]);

            // "Everything already has a current invoice": show that invoice so they can just pay it.
            if ($client && str_contains($e->getMessage(), 'already has a current invoice')) {
                $open = $this->existingOpenInvoiceFor($tenant, $client, $domain, $bundler, $account);
                if ($open) {
                    $this->offerPayment($tenant, $client, $phone, $open, $lang);
                    return;
                }
                $this->replyOrFinish($tenant, $client, $phone, $this->t($lang,
                    "Hakuna malipo yanayohitajika sasa hivi kwa {$domain->name}. Kama unahitaji msaada, wasiliana nasi.",
                    "There's nothing to pay right now for {$domain->name}. If you need help, please contact us."
                ), $lang);
                return;
            }

            $this->replyOrFinish($tenant, $client, $phone, $this->t($lang,
                'Samahani, hatuwezi kukamilisha ombi hili sasa hivi. Tafadhali jaribu tena baadaye au wasiliana nasi.',
                "Sorry, we couldn't complete this request right now. Please try again later or contact us."
            ), $lang);
            return;
        }

        if ($client) {
            $this->offerPayment($tenant, $client, $phone, $document, $lang);
        } else {
            $this->replyWithInvoice($tenant, $phone, $document, $lang);
        }
    }

    /** The client's already-open invoice covering this domain (its renewal invoice, or its hosting/domain subscriptions' open invoice). */
    private function existingOpenInvoiceFor(Tenant $tenant, Client $client, Domain $domain, RenewalBundleService $bundler, HostingAccount $account): ?Document
    {
        $doc = $this->openInvoice($tenant, $client, $domain->meta['renewal_document_id'] ?? null);
        if ($doc) {
            return $doc;
        }
        try {
            $subIds = array_map(fn ($s) => $s->id, $bundler->billableSubscriptions($account, true)['candidates']);
        } catch (\Throwable $e) {
            return null;
        }
        if (!$subIds) {
            return null;
        }
        $docIds = \App\Models\RecurringInvoiceLog::withoutGlobalScopes()->where('tenant_id', $tenant->id)->where('client_id', $client->id)
            ->whereIn('client_subscription_id', $subIds)->whereNotNull('document_id')->pluck('document_id');
        if ($docIds->isEmpty()) {
            return null;
        }

        return Document::withoutGlobalScopes()->where('tenant_id', $tenant->id)->where('client_id', $client->id)
            ->where('type', 'invoice')->whereIn('id', $docIds)->whereIn('status', ['sent', 'overdue', 'partial'])
            ->orderBy('due_date')->get()->first(fn ($d) => $d->balance_due > 0);
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
            "Andika jina la domain unalotaka kusajili (mfano: jinalako.co.tz).\n\n" . $this->menuFooter($lang),
            "Please reply with the domain name you want to register (e.g. yourname.co.tz).\n\n" . $this->menuFooter($lang)
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

            if (!$pricing || !$this->tldOrderable($pricing)) {
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
                $availability = app(DomainRegistrarManager::class)->checkFor($tenant->id, $name, $pricing);
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
            $this->reply($tenant, $phone, $this->availableDomainMessage($lang, $name, $price, 'order'));
            return;
        }

        if ($step === 'confirm') {
            $yes = $this->parseYesNo($text);
            if ($yes === null) {
                $this->invalidYesNo($tenant, $phone, $lang);
                return;
            }
            if (!$yes) {
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
            $yes = $this->parseYesNo($text);
            if ($yes === null) {
                $this->invalidYesNo($tenant, $phone, $lang);
                return;
            }
            if ($yes) {
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
        // Same split as PortalDomainController::order(): a Name.com-sold TLD is fulfilled by staff
        // (unmanaged, no FRED registrar account), everything else keeps the FRED path.
        $tldPricing = $action === 'register' ? DomainTld::priceFor($tenant->id, $this->extractTld($name) ?? '') : null;
        $viaNameCom = $tldPricing && $tldPricing->registrar === 'namecom';

        return DB::transaction(function () use ($tenant, $client, $name, $price, $registrar, $action, $authInfo, $verb, $viaNameCom) {
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
                'registrar_account_id' => $viaNameCom ? null : $registrar->accountFor($tenant->id)->id,
                'name' => $name,
                'status' => 'pending',
                'auto_renew' => false,
                'epp_auth_info' => $authInfo,
                'meta' => [
                    'pending_action' => $action,
                    'pending_years' => 1,
                    'order_document_id' => $document->id,
                    'whatsapp_order' => true,
                ] + ($viaNameCom ? ['unmanaged' => true, 'registrar' => 'namecom', 'namecom_years' => 1] : []),
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
            ->orderBy('price');
        $totalPlans = (clone $plans)->count();
        $plans = $plans->limit(9)->get();

        if ($plans->isEmpty()) {
            $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, hakuna vifurushi vinavyopatikana kwa sasa. Tafadhali wasiliana nasi.', 'Sorry, no plans are available right now. Please contact us.'), $lang);
            return;
        }

        $planIds = [];
        $lines = [];
        foreach ($plans as $plan) {
            $planIds[] = $plan->id;
            $lines[] = count($planIds) . ") {$plan->name} — TZS " . number_format((float) $plan->price) . ' ' . $this->cycleLabel($plan->billing_cycle, $lang);
        }

        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'flow' => 'order_hosting', 'state' => ['step' => 'pick_plan', 'category' => $category, 'plan_ids' => $planIds, 'domain' => $prefilledDomain], 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(10)],
        );

        $this->reply($tenant, $phone, $this->t($lang,
            "*Chagua kifurushi*\n\n" . implode("\n", $lines) . $this->moreNotice($tenant, $lang, $totalPlans - $plans->count(), false) . "\n\n" . $this->menuFooter($lang),
            "*Choose a plan*\n\n" . implode("\n", $lines) . $this->moreNotice($tenant, $lang, $totalPlans - $plans->count(), false) . "\n\n" . $this->menuFooter($lang)
        ));
    }

    private function handleOrderHostingStep(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, string $text, string $lang): void
    {
        $state = $session->state ?? [];
        $step = $state['step'] ?? 'pick_plan';

        // Picking a number shows that plan's full specs before anything is ordered. The specs screen is
        // its OWN confirmation step: 1/YES orders it, 2/NO goes back to the plan list — so a digit here can
        // never be mistaken for a pick from the earlier list.
        if ($step === 'pick_plan') {
            if (!preg_match('/^\s*([1-9])\s*$/', $text, $m) || empty($state['plan_ids'][$m[1] - 1])) {
                $this->invalidChoice($tenant, $phone, $lang, count($state['plan_ids'] ?? []));
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
            $price = 'TZS ' . number_format((float) $plan->price);
            $this->reply($tenant, $phone, $this->t($lang,
                "*{$plan->name}*\n• Bei: {$price} " . $this->cycleLabel($plan->billing_cycle, 'sw')
                    . ($specs ? "\n• Maelezo: {$specs}" : '')
                    . "\n\nUnataka kuagiza kifurushi hiki?\n1) Ndiyo, agiza hiki\n2) Hapana, chagua kingine",
                "*{$plan->name}*\n• Price: {$price} " . $this->cycleLabel($plan->billing_cycle, 'en')
                    . ($specs ? "\n• Details: {$specs}" : '')
                    . "\n\nOrder this plan?\n1) Yes, order this one\n2) No, choose another"
            ));
            return;
        }

        if ($step === 'plan_details') {
            $yes = $this->parseYesNo($text);
            if ($yes === null) {
                $this->reply($tenant, $phone, $this->t($lang,
                    "Samahani, jibu 1 au 2.\n\n1) Ndiyo, agiza hiki\n2) Hapana, chagua kingine",
                    "Sorry, reply 1 or 2.\n\n1) Yes, order this one\n2) No, choose another"
                ));
                return;
            }
            if (!$yes) {
                $this->startOrderHosting($tenant, $client, $phone, (string) ($state['category'] ?? 'Web Hosting'), $lang, $state['domain'] ?? null);
                return;
            }

            $plan = ProductService::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($state['product_service_id'] ?? null);
            if (!$plan) {
                $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, kifurushi hicho hakipatikani tena. Tafadhali jaribu tena.', 'Sorry, that plan is no longer available. Please try again.'), $lang);
                return;
            }

            // Already have a domain (continuing straight from a domain order) —
            // skip straight to the promo-code step instead of asking for it again.
            if (!empty($state['domain'])) {
                $session->update(['state' => array_merge($state, ['step' => 'ask_promo', 'product_service_id' => $plan->id])]);
                $this->reply($tenant, $phone, $this->promoPrompt($lang));
                return;
            }

            $session->update(['state' => array_merge($state, ['step' => 'ask_domain_mode', 'product_service_id' => $plan->id])]);
            $this->reply($tenant, $phone, $this->t($lang,
                "Umechagua *{$plan->name}*. Domain:\n\n1) Ninayo tayari (nitaweka DNS mwenyewe)\n2) Nisajilie domain mpya\n3) Nihamishie (transfer) domain yangu kwenu\n\n" . $this->menuFooter($lang),
                "You've chosen *{$plan->name}*. Domain:\n\n1) I already have one (I'll point the DNS myself)\n2) Register a new domain for me\n3) Transfer my domain to you\n\n" . $this->menuFooter($lang)
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
                        "Andika jina la domain la huduma hii (lililopo tayari).\n\n" . $this->menuFooter($lang),
                        "Please reply with the domain name for this service (one you already have).\n\n" . $this->menuFooter($lang)
                    ));
                })(),
                (bool) preg_match('/^\s*2\s*$/', $text) => (function () use ($tenant, $phone, $session, $state, $lang) {
                    $session->update(['state' => array_merge($state, ['step' => 'register_domain_name'])]);
                    $this->reply($tenant, $phone, $this->t($lang,
                        "Andika jina la domain unalotaka kusajili (mfano: jinalako.co.tz).\n\n" . $this->menuFooter($lang),
                        "Please reply with the domain name you want to register (e.g. yourname.co.tz).\n\n" . $this->menuFooter($lang)
                    ));
                })(),
                (bool) preg_match('/^\s*3\s*$/', $text) => (function () use ($tenant, $phone, $session, $state, $lang) {
                    $session->update(['state' => array_merge($state, ['step' => 'transfer_domain_name'])]);
                    $this->reply($tenant, $phone, $this->t($lang,
                        "Andika jina la domain unalotaka kuhamishia kwetu (mfano: jinalako.co.tz).\n\n" . $this->menuFooter($lang),
                        "Please reply with the domain name you want to transfer to us (e.g. yourname.co.tz).\n\n" . $this->menuFooter($lang)
                    ));
                })(),
                default => $this->invalidChoice($tenant, $phone, $lang, 3),
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
                    "*Kuhamisha {$name}*\n• Bei: TZS " . number_format($price) . "\n\nAndika EPP/Auth code ya domain hii (unaipata kwa msajili wako wa sasa).\n\n" . $this->menuFooter($lang),
                    "*Transfer {$name}*\n• Price: TZS " . number_format($price) . "\n\nPlease reply with this domain's EPP/Auth code (get it from your current registrar).\n\n" . $this->menuFooter($lang)
                ));
                return;
            }

            $session->update(['state' => array_merge($state, ['step' => 'register_domain_confirm', 'domain' => $name, 'domain_price' => $price])]);
            $this->reply($tenant, $phone, $this->availableDomainMessage($lang, $name, $price, 'continue'));
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
                $this->confirmMessage('sw', 'Thibitisha kuhamisha domain', ["Domain: {$state['domain']}", 'Bei: TZS ' . number_format((float) $state['domain_price'])], 'Endelea?'),
                $this->confirmMessage('en', 'Confirm domain transfer', ["Domain: {$state['domain']}", 'Price: TZS ' . number_format((float) $state['domain_price'])], 'Continue?')
            ));
            return;
        }

        if ($step === 'register_domain_confirm' || $step === 'transfer_domain_confirm') {
            $yes = $this->parseYesNo($text);
            if ($yes === null) {
                $this->invalidYesNo($tenant, $phone, $lang);
                return;
            }
            if (!$yes) {
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
            $this->reply($tenant, $phone, $this->promoPrompt($lang));
            return;
        }

        if ($step === 'ask_promo') {
            $plan = ProductService::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($state['product_service_id'] ?? null);
            $domain = $state['domain'] ?? null;
            if (!$plan || !$domain) {
                $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, kuna hitilafu. Tafadhali jaribu tena.', 'Sorry, something went wrong. Please try again.'), $lang);
                return;
            }

            // "no promo": the word (HAPANA/NO/HAKUNA/SKIP) or the digit 2 shown in the prompt.
            if (preg_match('/^\s*(2|hapana|no|hakuna|skip)\s*$/i', $text)) {
                $session->update(['state' => array_merge($state, ['step' => 'confirm', 'coupon_id' => null])]);
                $this->reply($tenant, $phone, $this->orderConfirmMessage($lang, $plan, (float) $plan->price, $domain));
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
            $this->reply($tenant, $phone, $this->orderConfirmMessage($lang, $plan, $total, $domain, $coupon->code, $discount));
            return;
        }

        if ($step === 'confirm') {
            $yes = $this->parseYesNo($text);
            if ($yes === null) {
                $this->invalidYesNo($tenant, $phone, $lang);
                return;
            }
            if (!$yes) {
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

    private function promoPrompt(string $lang): string
    {
        return $this->t($lang,
            "Una promo code?\n• Andika code yako hapa, au\n• Jibu 2 (Hapana) kama huna.\n\n" . $this->menuFooter($lang),
            "Have a promo code?\n• Type your code here, or\n• Reply 2 (No) if you don't have one.\n\n" . $this->menuFooter($lang)
        );
    }

    /** Compact hosting-order confirmation (also used after a promo is applied). */
    private function orderConfirmMessage(string $lang, ProductService $plan, float $price, string $domain, ?string $promo = null, float $discount = 0.0): string
    {
        $mk = fn (string $l) => $this->confirmMessage($l,
            $this->t($l, $promo ? "Promo {$promo} imekubalika" : 'Thibitisha agizo', $promo ? "Promo {$promo} applied" : 'Confirm your order'),
            array_merge(
                [$this->t($l, "Kifurushi: {$plan->name}", "Package: {$plan->name}")],
                [$this->t($l, 'Bei: TZS ' . number_format($price) . ' ' . $this->cycleLabel($plan->billing_cycle, 'sw'), 'Price: TZS ' . number_format($price) . ' ' . $this->cycleLabel($plan->billing_cycle, 'en'))],
                $promo ? [$this->t($l, 'Punguzo: TZS ' . number_format($discount), 'Discount: TZS ' . number_format($discount))] : [],
                ["Domain: {$domain}"]
            ),
            $this->t($l, 'Unataka kuagiza?', 'Place the order?')
        );

        return $this->t($lang, $mk('sw'), $mk('en'));
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
    private function paymentMethodMessage(string $lang, Document $doc, float $amount): string
    {
        return $this->t($lang,
            "*Invoice {$doc->document_number}*\n• Kiasi: TZS " . number_format($amount) . "\n\nChagua njia ya kulipa:\n1) Lipa mtandaoni (Kadi / Mobile Money)\n2) Maelezo ya kulipa (Benki/Lipa Namba)\n\n" . $this->menuFooter($lang),
            "*Invoice {$doc->document_number}*\n• Amount: TZS " . number_format($amount) . "\n\nChoose how to pay:\n1) Pay online (Card / Mobile Money)\n2) Payment details (Bank/mobile money)\n\n" . $this->menuFooter($lang)
        );
    }

    private function offerPayment(Tenant $tenant, Client $client, string $phone, Document $document, string $lang, ?array $after = null): void
    {
        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'flow' => 'pay_invoice', 'state' => ['step' => 'choose_method', 'document_id' => $document->id, 'after' => $after], 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(10)],
        );

        $this->reply($tenant, $phone, $this->paymentMethodMessage($lang, $document, (float) $document->total));
    }

    private function startPayInvoice(Tenant $tenant, Client $client, string $phone, string $lang, ?string $query = null): void
    {
        $base = Document::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->where('client_id', $client->id)
            ->where('type', 'invoice')
            ->whereIn('status', ['sent', 'overdue', 'partial'])
            ->orderBy('due_date');
        if ($query !== null) {
            $base->where('document_number', 'like', '%' . addcslashes($query, '%_\\') . '%');
        }
        $total = (clone $base)->count();
        $invoices = $base->limit(9)->get();

        if ($invoices->isEmpty() && $query !== null) {
            $this->reply($tenant, $phone, $this->t($lang,
                "Hakuna invoice inayolingana na \"{$query}\". Jaribu namba nyingine, au:\n\n" . $this->menuFooter($lang),
                "No invoice matches \"{$query}\". Try another number, or:\n\n" . $this->menuFooter($lang)
            ));
            return;
        }

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
            $overdue = $doc->status === 'overdue' || ($doc->due_date && $doc->due_date->isPast() && !$doc->due_date->isToday());
            $lines[] = count($docIds) . ') ' . ($overdue ? '⚠️' : '⏳') . " {$doc->document_number} — TZS {$balance} (deadline {$due})";
        }

        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'flow' => 'pay_invoice', 'state' => ['step' => 'pick_invoice', 'doc_ids' => $docIds, 'capped' => $total > $invoices->count()], 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(10)],
        );

        $this->reply($tenant, $phone, $this->t($lang,
            "*Invoice zako zisizolipwa*\n\n" . implode("\n", $lines) . $this->moreNotice($tenant, $lang, $total - $invoices->count(), true, '/portal/invoices') . "\n\nJibu na namba kuchagua.\n\n" . $this->menuFooter($lang),
            "*Your unpaid invoices*\n\n" . implode("\n", $lines) . $this->moreNotice($tenant, $lang, $total - $invoices->count(), true, '/portal/invoices') . "\n\nReply with a number to choose.\n\n" . $this->menuFooter($lang)
        ));
    }

    private function handlePayInvoiceStep(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, string $text, string $lang): void
    {
        $state = $session->state ?? [];
        $step = $state['step'] ?? 'pick_invoice';

        if ($step === 'pick_invoice') {
            if (!empty($state['capped']) && !preg_match('/^\s*\d+\s*$/', $text) && mb_strlen(trim($text)) >= 2) {
                $this->startPayInvoice($tenant, $client, $phone, $lang, trim($text));
                return;
            }
            if (!preg_match('/^\s*([1-9])\s*$/', $text, $m) || empty($state['doc_ids'][$m[1] - 1])) {
                $this->invalidChoice($tenant, $phone, $lang, count($state['doc_ids'] ?? []));
                return;
            }

            $docId = $state['doc_ids'][$m[1] - 1];
            $doc = Document::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($docId);
            if (!$doc) {
                $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, invoice hiyo haipatikani tena. Tafadhali jaribu tena.', 'Sorry, that invoice is no longer available. Please try again.'), $lang);
                return;
            }

            $session->update(['state' => ['step' => 'choose_method', 'document_id' => $doc->id]]);
            $this->reply($tenant, $phone, $this->paymentMethodMessage($lang, $doc, (float) $doc->balance_due));
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

            $this->invalidChoice($tenant, $phone, $lang, 2);
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
                $this->confirmMessage('sw', 'Website Hosting', ["Domain: {$domain}"], "Unataka pia hosting kwenye {$domain}?"),
                $this->confirmMessage('en', 'Website Hosting', ["Domain: {$domain}"], "Would you also like hosting on {$domain}?")
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
                $this->reply($tenant, $phone, $this->orderConfirmMessage($lang, $plan, (float) $plan->price, $after['domain']));
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
            "Andika jina la domain (.tz) unalotaka kuangalia taarifa zake (mfano: jinalako.co.tz).\n\n" . $this->menuFooter($lang),
            "Please reply with the .tz domain name you want to look up (e.g. yourname.co.tz).\n\n" . $this->menuFooter($lang)
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

        $this->finishFlow($tenant, $client, $phone, implode("\n", array_filter([
            "*Domain: {$name}*",
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
            "Andika jina la domain unalotaka kuangalia (mfano: jinalako au jinalako.co.tz). Nitakuonyesha TLD kadhaa na bei.\n\n" . $this->menuFooter($lang),
            "Please reply with the domain name you want to check (e.g. yourname or yourname.co.tz). I will show several extensions with prices.\n\n" . $this->menuFooter($lang)
        ));
    }

    /** A TLD can be ordered instantly when Name.com sells it, or when it is a real (managed) registry TLD. */
    private function tldOrderable(DomainTld $pricing): bool
    {
        return $pricing->registrar === 'namecom' || !$pricing->is_unmanaged;
    }

    private const AVAILABILITY_ROWS = 8;

    private function handleCheckAvailabilityStep(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, string $text, string $lang): void
    {
        $state = $session->state ?? [];

        // A digit after a results list picks a row to order (list lives in the session state).
        if (preg_match('/^\s*(\d{1,2})\s*$/', $text, $m)) {
            if (($state['step'] ?? '') !== 'pick' || empty($state['rows'])) {
                $this->reply($tenant, $phone, $this->t($lang,
                    'Andika jina la domain unalotaka kuangalia (mfano: jinalako au jinalako.co.tz), au MENU kurudi.',
                    'Please type the domain name you want to check (e.g. yourname or yourname.co.tz), or MENU to go back.'
                ));
                return;
            }
            $this->pickAvailabilityRow($tenant, $client, $phone, $session, (int) $m[1], $state, $lang);
            return;
        }

        $parsed = DomainSuggestService::parse($text);
        if (!$parsed) {
            $this->reply($tenant, $phone, $this->t($lang,
                'Samahani, jina hilo halionekani sahihi. Andika kama: jinalako au jinalako.co.tz',
                "Sorry, that doesn't look like a valid domain. Reply like: yourname or yourname.co.tz"
            ));
            return;
        }

        $rows = null;
        try {
            $svc = app(DomainSuggestService::class);
            $rows = $svc->check($tenant->id, $svc->plan($tenant->id, $parsed['label'], $parsed['tld'], 'portal', null, self::AVAILABILITY_ROWS));
        } catch (\Throwable $e) {
            Log::warning('WhatsApp check_availability suggestions failed', ['label' => $parsed['label'], 'error' => $e->getMessage()]);
            $rows = null;
        }

        $usable = $rows ? array_filter($rows, fn ($r) => in_array($r['status'], ['available', 'taken', 'unavailable'], true)) : [];
        if (!$usable) {
            // Suggestions unavailable (or nothing checkable): keep the single-domain behaviour.
            if ($parsed['tld']) {
                $this->checkSingleDomain($tenant, $client, $phone, $parsed['label'] . '.' . $parsed['tld'], $lang);
            } else {
                $this->reply($tenant, $phone, $this->t($lang,
                    'Samahani, imeshindikana kuangalia domain hii sasa hivi. Andika jina lenye TLD (mfano jinalako.co.tz) au jaribu tena baadaye.',
                    "Sorry, we couldn't check this right now. Try a full name with its extension (e.g. yourname.co.tz) or try again later."
                ));
            }
            return;
        }

        // A name we already hold is never orderable, whatever the registry says.
        $names = array_column($rows, 'name');
        $heldHere = Domain::withoutGlobalScopes()->whereIn('name', $names)->whereNotIn('status', ['cancelled', 'transferred_out'])->pluck('name')->all();

        $sw = $lang === 'sw';
        $lines = [$sw ? "*Matokeo ya domain: {$parsed['label']}*" : "*Domain search: {$parsed['label']}*", ''];
        $stateRows = [];
        $anyAvailable = false;
        foreach ($rows as $i => $r) {
            $n = $i + 1;
            if ($r['status'] === 'available' && in_array($r['name'], $heldHere, true)) {
                $r['status'] = 'taken';
            }
            $orderable = $r['status'] === 'available' && $r['register_price'] !== null;
            $anyAvailable = $anyAvailable || $orderable;
            $stateRows[] = ['name' => $r['name'], 'ok' => $orderable];
            $label = match (true) {
                $orderable => ($sw ? 'INAPATIKANA — TZS ' : 'Available — TZS ') . number_format((float) $r['register_price']) . ($sw ? '/mwaka' : '/yr'),
                in_array($r['status'], ['taken', 'unavailable'], true) => $sw ? 'Imeshasajiliwa' : 'Taken',
                $r['status'] === 'not_offered' => $sw ? 'Hatutoi TLD hii' : 'Not offered',
                default => $sw ? 'Haiwezi kuangaliwa sasa' : "Can't check right now",
            };
            $lines[] = "{$n}) {$r['name']} — {$label}";
        }
        $lines[] = '';
        $lines[] = $anyAvailable
            ? ($sw ? 'Jibu na namba kuagiza domain, au andika jina lingine kutafuta tena.' : 'Reply with a number to order, or type another name to search again.')
            : ($sw ? 'Andika jina lingine kutafuta tena.' : 'Type another name to search again.');
        $lines[] = '';
        $lines[] = $this->menuFooter($lang);

        $session->update(['state' => ['step' => 'pick', 'rows' => $stateRows], 'expires_at' => now()->addMinutes(10)]);
        $this->reply($tenant, $phone, implode("\n", $lines));
    }

    /** Ordering from a search result: hands the name to the existing registration flow at its confirm step. */
    private function pickAvailabilityRow(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, int $n, array $state, string $lang): void
    {
        $row = $state['rows'][$n - 1] ?? null;
        if (!$row) {
            $this->invalidChoice($tenant, $phone, $lang, count($state['rows'] ?? []));
            return;
        }
        if (empty($row['ok'])) {
            $this->reply($tenant, $phone, $this->t($lang,
                "Samahani, {$row['name']} haipatikani kuagizwa. Chagua namba nyingine au andika jina lingine.",
                "Sorry, {$row['name']} can't be ordered. Choose another number or type another name."
            ));
            return;
        }

        $name = $row['name'];
        $tld = $this->extractTld($name);
        $pricing = $tld ? DomainTld::priceFor($tenant->id, $tld) : null;
        if (!$pricing || !$this->tldOrderable($pricing)
            || Domain::withoutGlobalScopes()->where('name', $name)->whereNotIn('status', ['cancelled', 'transferred_out'])->exists()) {
            $this->reply($tenant, $phone, $this->t($lang,
                "Samahani, {$name} haipatikani kuagizwa sasa. Chagua namba nyingine au andika jina lingine.",
                "Sorry, {$name} can't be ordered right now. Choose another number or type another name."
            ));
            return;
        }

        $price = (float) $pricing->register_price;
        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'flow' => 'order_domain', 'state' => ['step' => 'confirm', 'domain' => $name, 'price' => $price], 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(10)],
        );
        $this->reply($tenant, $phone, $this->availableDomainMessage($lang, $name, $price, 'order'));
    }

    /** The original single-domain check — kept as the fallback when multi-TLD suggestions are unavailable. */
    private function checkSingleDomain(Tenant $tenant, Client $client, string $phone, string $name, string $lang): void
    {
        $tld = $this->extractTld($name);
        $pricing = $tld ? DomainTld::priceFor($tenant->id, $tld) : null;

        if (!$pricing || !$this->tldOrderable($pricing)) {
            $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, hatuwezi kuangalia aina hii ya domain papo hapo. Tafadhali wasiliana nasi.', "Sorry, we can't check this domain type instantly. Please contact us."), $lang);
            return;
        }

        try {
            $availability = app(DomainRegistrarManager::class)->checkFor($tenant->id, $name, $pricing);
        } catch (\Throwable $e) {
            Log::warning('WhatsApp check_availability failed', ['name' => $name, 'error' => $e->getMessage()]);
            $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, imeshindikana kuangalia domain hii sasa hivi. Jaribu tena baadaye.', "Sorry, we couldn't check this domain right now. Please try again later."), $lang);
            return;
        }

        if ($availability['available'] ?? false) {
            // Same hand-off as picking a search row: straight into the registration confirm step.
            $price = (float) $pricing->register_price;
            WhatsappRenewalSession::updateOrCreate(
                ['tenant_id' => $tenant->id, 'phone' => $phone],
                ['client_id' => $client->id, 'flow' => 'order_domain', 'state' => ['step' => 'confirm', 'domain' => $name, 'price' => $price], 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(10)],
            );
            $this->reply($tenant, $phone, $this->availableDomainMessage($lang, $name, $price, 'order'));
        } else {
            $this->finishFlow($tenant, $client, $phone, $this->t($lang, "Domain {$name} tayari limesajiliwa — halipatikani.", "Domain {$name} is already registered — not available."), $lang);
        }
    }

    // ── Nameserver / DNS change ─────────────────────────────────────────

    private function startChangeDns(Tenant $tenant, Client $client, string $phone, string $lang, ?string $query = null): void
    {
        $domains = Domain::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->where('client_id', $client->id)
            ->whereIn('status', ['active', 'expired'])
            ->orderBy('name');
        if ($query !== null) {
            $domains->where('name', 'like', '%' . addcslashes($query, '%_\\') . '%');
        }
        $totalDomains = (clone $domains)->count();
        $domains = $domains->limit(9)->get();

        if ($domains->isEmpty() && $query !== null) {
            $this->reply($tenant, $phone, $this->t($lang,
                "Hakuna domain inayolingana na \"{$query}\". Jaribu jina lingine, au:\n\n" . $this->menuFooter($lang),
                "No domain matches \"{$query}\". Try another name, or:\n\n" . $this->menuFooter($lang)
            ));
            return;
        }

        if ($domains->isEmpty()) {
            $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Huna domain iliyosajiliwa kwa sasa.', "You don't have any registered domains right now."), $lang);
            return;
        }

        $domainIds = $domains->pluck('id')->all();
        $lines = $domains->values()->map(fn ($d, $i) => ($i + 1) . ") {$d->name}")->implode("\n");
        $lines .= $this->moreNotice($tenant, $lang, $totalDomains - $domains->count(), true);

        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'flow' => 'change_dns', 'state' => ['step' => 'pick_domain', 'domain_ids' => $domainIds, 'capped' => $totalDomains > $domains->count()], 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(10)],
        );

        $this->reply($tenant, $phone, $this->t($lang,
            "*Chagua domain unayotaka kubadilisha nameservers*\n\n{$lines}\n\n" . $this->menuFooter($lang),
            "*Choose the domain to change nameservers for*\n\n{$lines}\n\n" . $this->menuFooter($lang)
        ));
    }

    private function handleChangeDnsStep(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, string $text, string $lang): void
    {
        $state = $session->state ?? [];
        $step = $state['step'] ?? 'pick_domain';

        if ($step === 'pick_domain') {
            if (!empty($state['capped']) && !preg_match('/^\s*\d+\s*$/', $text) && mb_strlen(trim($text)) >= 2) {
                $this->startChangeDns($tenant, $client, $phone, $lang, trim($text));
                return;
            }
            if (!preg_match('/^\s*([1-9])\s*$/', $text, $m) || empty($state['domain_ids'][$m[1] - 1])) {
                $this->invalidChoice($tenant, $phone, $lang, count($state['domain_ids'] ?? []));
                return;
            }

            $domain = Domain::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($state['domain_ids'][$m[1] - 1]);
            if (!$domain) {
                $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, domain hiyo haipatikani tena. Tafadhali jaribu tena.', 'Sorry, that domain is no longer available. Please try again.'), $lang);
                return;
            }

            $session->update(['state' => ['step' => 'ask_nameservers', 'domain_id' => $domain->id]]);
            $this->reply($tenant, $phone, $this->t($lang,
                "Andika nameservers mbili au zaidi za {$domain->name}, zikitenganishwa na koma. Mfano: ns1.example.com, ns2.example.com\n\n" . $this->menuFooter($lang),
                "Please reply with two or more nameservers for {$domain->name}, separated by commas. Example: ns1.example.com, ns2.example.com\n\n" . $this->menuFooter($lang)
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
            $dnsDomain = Domain::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($state['domain_id'] ?? null);
            $this->reply($tenant, $phone, $this->t($lang,
                $this->confirmMessage('sw', 'Thibitisha kubadilisha nameservers', ['Domain: ' . ($dnsDomain?->name ?? '—'), 'Nameservers: ' . implode(', ', $nameservers)], 'Badilisha sasa?'),
                $this->confirmMessage('en', 'Confirm nameserver change', ['Domain: ' . ($dnsDomain?->name ?? '—'), 'Nameservers: ' . implode(', ', $nameservers)], 'Change them now?')
            ));
            return;
        }

        if ($step === 'confirm') {
            $yes = $this->parseYesNo($text);
            if ($yes === null) {
                $this->invalidYesNo($tenant, $phone, $lang);
                return;
            }
            if (!$yes) {
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
    /** WhatsApp text messages max out around 4096 chars; stay well under and split on line boundaries. */
    private const MAX_REPLY_CHARS = 3900;

    /** @return string[] */
    private function splitMessage(string $message, int $max = self::MAX_REPLY_CHARS): array
    {
        if (mb_strlen($message) <= $max) {
            return [$message];
        }
        $parts = [];
        $cur = '';
        foreach (explode("\n", $message) as $line) {
            // a single absurdly long line is hard-cut
            while (mb_strlen($line) > $max) {
                if ($cur !== '') {
                    $parts[] = $cur;
                    $cur = '';
                }
                $parts[] = mb_substr($line, 0, $max);
                $line = mb_substr($line, $max);
            }
            $candidate = $cur === '' ? $line : $cur . "\n" . $line;
            if (mb_strlen($candidate) > $max) {
                $parts[] = $cur;
                $cur = $line;
            } else {
                $cur = $candidate;
            }
        }
        if ($cur !== '') {
            $parts[] = $cur;
        }

        return $parts;
    }

    private function reply(Tenant $tenant, string $phone, string $message): void
    {
        foreach ($this->splitMessage($message) as $part) {
            try {
                app(WhatsAppService::class)->sendSessionText($tenant, $phone, $part);
            } catch (\Throwable $e) {
                $this->noteSendFailure($tenant, $phone, $e);
                return; // the rest of a failed conversation turn would fail the same way
            }
        }
    }

    /** Logs a failed send with tenant/phone; a balance-style failure also alerts staff (once an hour per tenant). */
    private function noteSendFailure(Tenant $tenant, string $phone, \Throwable $e): void
    {
        Log::warning('WhatsApp renewal reply send failed', ['tenant_id' => $tenant->id, 'phone' => $phone, 'error' => $e->getMessage()]);

        if (!preg_match('/balance|insufficient|credit|not enough|\b422\b/i', $e->getMessage())) {
            return;
        }
        try {
            if (!\Illuminate\Support\Facades\Cache::add("wa_bot_send_alert:{$tenant->id}", 1, 3600)) {
                return;
            }
            $this->notifyStaff($tenant, 'settings.company', new \App\Notifications\WhatsappBotAlertNotification(
                'send_failed',
                'WhatsApp bot cannot send replies',
                'The WhatsApp self-service bot failed to send a reply (' . mb_substr($e->getMessage(), 0, 150) . '). Clients are getting no answer - please check the WhatsApp/MoSMS balance.',
                '/settings',
            ));
        } catch (\Throwable $x) {
            report($x);
        }
    }

    private function notifyStaff(Tenant $tenant, string $permission, \Illuminate\Notifications\Notification $notification): void
    {
        $staff = User::withPermission($tenant->id, $permission);
        if ($staff->isNotEmpty()) {
            \Illuminate\Support\Facades\Notification::send($staff, $notification);
        }
    }

    /** More than 30 inbound messages per phone in 10 minutes: one polite notice, then silence for the rest of the window. */
    private function inboundRateLimited(Tenant $tenant, string $phone): bool
    {
        try {
            $key = "wa_inbound_rl:{$tenant->id}:{$phone}";
            \Illuminate\Support\Facades\Cache::add($key, 0, 600);
            $n = \Illuminate\Support\Facades\Cache::increment($key);
        } catch (\Throwable $e) {
            return false; // never block a client because the cache misbehaved
        }
        $limit = (int) config('services.mosms.inbound_rate_limit', 30);
        if ($n <= $limit) {
            return false;
        }
        if ($n === $limit + 1) {
            $this->reply($tenant, $phone, "Tafadhali subiri kidogo, umetuma ujumbe mwingi. Jaribu tena baada ya dakika chache.\nPlease wait a little, you have sent many messages. Try again in a few minutes.");
        }

        return true;
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
            $this->noteSendFailure($tenant, $phone, $e);
            $this->reply($tenant, $phone, "{$text} {$url}");
        }
    }
}
