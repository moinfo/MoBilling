<?php

namespace App\Http\Controllers;

use App\Helpers\PhoneHelper;
use App\Models\Client;
use App\Models\Document;
use App\Models\Domain;
use App\Models\DomainTld;
use App\Models\HostingAccount;
use App\Models\MosmsAccount;
use App\Models\PesapalInvoicePayment;
use App\Models\ProductService;
use App\Models\Tenant;
use App\Models\WhatsappRenewalSession;
use App\Services\DocumentNumberService;
use App\Services\Hosting\RenewalBundleService;
use App\Services\Registrar\DomainRegistrarManager;
use App\Services\TenantPesapalService;
use App\Services\TznicWhoisService;
use App\Services\WhatsAppService;
use Illuminate\Http\Request;
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
        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'flow' => null, 'state' => null, 'items' => null, 'language' => $lang, 'confirmed_at' => now(), 'expires_at' => now()->addDays(30)],
        );

        $this->reply($tenant, $phone, $this->t($lang,
            "Habari {$client->name}! Chagua huduma: "
                . '1) Domain Registration · 2) Domain Renewal · 3) Website Hosting · '
                . '4) Business Email Hosting · 5) Angalia na Lipa Invoice · '
                . '6) WHOIS ya Domain · 7) Angalia kama Domain Inapatikana · '
                . '8) Badilisha Nameservers (DNS) · '
                . '0) Toka (Logout). Jibu na namba.',
            "Hi {$client->name}! Choose a service: "
                . '1) Domain Registration · 2) Domain Renewal · 3) Website Hosting · '
                . '4) Business Email Hosting · 5) View and Pay Invoices · '
                . '6) Domain WHOIS · 7) Check Domain Availability · '
                . '8) Change Nameservers (DNS) · '
                . '0) Logout. Reply with a number.'
        ));
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
            (bool) preg_match('/^\s*3\s*$/', $text) => $this->startOrderHosting($tenant, $client, $phone, 'Web Hosting', $lang),
            (bool) preg_match('/^\s*4\s*$/', $text) => $this->startOrderHosting($tenant, $client, $phone, 'Business E-mail', $lang),
            (bool) preg_match('/^\s*5\s*$/', $text) => $this->startPayInvoice($tenant, $client, $phone, $lang),
            (bool) preg_match('/^\s*6\s*$/', $text) => $this->startWhois($tenant, $client, $phone, $lang),
            (bool) preg_match('/^\s*7\s*$/', $text) => $this->startCheckAvailability($tenant, $client, $phone, $lang),
            (bool) preg_match('/^\s*8\s*$/', $text) => $this->startChangeDns($tenant, $client, $phone, $lang),
            default => $this->sendRootMenu($tenant, $client, $phone, $lang),
        };
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
                    // skip straight to confirming instead of asking for it again.
                    if (!empty($state['domain'])) {
                        $session->update(['state' => array_merge($state, ['step' => 'confirm', 'product_service_id' => $plan->id])]);
                        $this->reply($tenant, $phone, $this->t($lang,
                            "Thibitisha: {$plan->name} — TZS " . number_format((float) $plan->price) . "/{$plan->billing_cycle}, domain: {$state['domain']}. Jibu NDIYO kuagiza.",
                            "Confirm: {$plan->name} — TZS " . number_format((float) $plan->price) . "/{$plan->billing_cycle}, domain: {$state['domain']}. Reply YES to order."
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

            $session->update(['state' => array_merge($state, ['step' => 'confirm', 'domain' => $name])]);
            $this->reply($tenant, $phone, $this->t($lang,
                "Thibitisha: {$plan->name} — TZS " . number_format((float) $plan->price) . "/{$plan->billing_cycle}, domain: {$name}. Jibu NDIYO kuagiza.",
                "Confirm: {$plan->name} — TZS " . number_format((float) $plan->price) . "/{$plan->billing_cycle}, domain: {$name}. Reply YES to order."
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

            if (!$plan || !$domain) {
                $this->finishFlow($tenant, $client, $phone, $this->t($lang, 'Samahani, kuna hitilafu. Tafadhali jaribu tena.', 'Sorry, something went wrong. Please try again.'), $lang);
                return;
            }

            try {
                $document = $this->createHostingOrder($tenant, $client, $plan, $domain);
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
     * product on an existing domain (domain_mode='existing') — no coupons,
     * add-ons or config options, not exposed in this chat flow.
     */
    private function createHostingOrder(Tenant $tenant, Client $client, ProductService $plan, string $domain): Document
    {
        return DB::transaction(function () use ($tenant, $client, $plan, $domain) {
            $subscription = \App\Models\ClientSubscription::withoutGlobalScopes()->create([
                'tenant_id' => $tenant->id,
                'client_id' => $client->id,
                'product_service_id' => $plan->id,
                'label' => $domain,
                'quantity' => 1,
                'status' => 'pending',
                'start_date' => now()->toDateString(),
                'metadata' => ['domain' => $domain, 'whatsapp_order' => true],
            ]);

            $total = round((float) $plan->price, 2);

            $document = Document::withoutGlobalScopes()->create([
                'tenant_id' => $tenant->id,
                'client_id' => $client->id,
                'type' => 'invoice',
                'document_number' => app(DocumentNumberService::class)->generate('invoice', $tenant->id),
                'date' => now()->toDateString(),
                'due_date' => now()->addDays(7)->toDateString(),
                'subtotal' => $total,
                'discount_amount' => 0,
                'tax_amount' => 0,
                'total' => $total,
                'status' => 'sent',
                'notes' => "{$plan->name} (WhatsApp order): {$domain}",
            ]);

            $document->items()->create([
                'item_type' => 'service',
                'description' => "{$plan->name} — {$domain}",
                'quantity' => 1,
                'price' => $plan->price,
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
