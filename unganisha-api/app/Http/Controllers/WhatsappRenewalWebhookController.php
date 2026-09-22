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
 *    self-service catch-all (root menu: renewals, new domain/hosting
 *    orders, unpaid invoices, WHOIS, availability check).
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
            $this->reply($tenant, $phone, 'Samahani, muda wa kujibu umepita. Tafadhali wasiliana nasi au ingia kwenye client portal kufanya renewal.');
            return response('OK', 200);
        }

        $this->pickAndGenerate($tenant, null, $phone, $session, 1, $bundler);

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

        if ($session && !$session->isExpired() && $session->flow === 'register') {
            $this->handleRegistrationStep($tenant, $phone, $session, $text);
            return response('OK', 200);
        }

        if ($session && !$session->isExpired() && $session->confirmed_at) {
            $client = Client::withoutGlobalScopes()->find($session->client_id);
            if (!$client) {
                $session->delete();
                $this->reply($tenant, $phone, 'Samahani, kuna hitilafu. Tafadhali wasiliana nasi.');
                return response('OK', 200);
            }

            match ($session->flow) {
                'order_domain' => $this->handleOrderDomainStep($tenant, $client, $phone, $session, $text),
                'order_hosting' => $this->handleOrderHostingStep($tenant, $client, $phone, $session, $text),
                'pay_invoice' => $this->handlePayInvoiceStep($tenant, $client, $phone, $session, $text),
                'whois' => $this->handleWhoisStep($tenant, $client, $phone, $session, $text),
                'check_availability' => $this->handleCheckAvailabilityStep($tenant, $client, $phone, $session, $text),
                default => $this->handleRootStep($tenant, $client, $phone, $session, $text, $bundler),
            };

            return response('OK', 200);
        }

        if ($session && !$session->isExpired() && !$session->confirmed_at) {
            $this->handleSurnameStep($tenant, $phone, $session, $text);
            return response('OK', 200);
        }

        $client = Client::withoutGlobalScopes()->where('tenant_id', $tenant->id);
        $client = PhoneHelper::wherePhone($client, 'phone', $phone)->first();

        if (!$client) {
            // Most-recent-sender attribution is a heuristic, not proof this phone belongs
            // to a Moinfotech customer at all — but if they're replying to something we
            // genuinely just sent them, self-registration is the reasonable next step
            // rather than staying silent.
            $this->startRegistration($tenant, $phone);
            return response('OK', 200);
        }

        // Identity is not proven by the phone match alone — ask for the surname registered
        // with MoBilling before showing any account details, exactly as requested (mirrors
        // how DStv's own WhatsApp bot verifies before revealing account info).
        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'items' => null, 'flow' => null, 'state' => null, 'confirmed_at' => null, 'attempts' => 0, 'expires_at' => now()->addMinutes(10)],
        );

        $this->reply($tenant, $phone,
            'Karibu MoBilling! Kwa uthibitisho, tafadhali jibu kwa jina lako la ukoo (surname) lililosajiliwa.');

        return response('OK', 200);
    }

    // ── Identity ─────────────────────────────────────────────────────────

    private function startRegistration(Tenant $tenant, string $phone): void
    {
        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => null, 'flow' => 'register', 'state' => ['step' => 'ask_name'], 'items' => null, 'confirmed_at' => null, 'attempts' => 0, 'expires_at' => now()->addMinutes(10)],
        );

        $this->reply($tenant, $phone, 'Karibu MoBilling! Bado hujasajiliwa. Tafadhali andika jina lako kamili (jina la kwanza na la ukoo) kujisajili.');
    }

    private function handleRegistrationStep(Tenant $tenant, string $phone, WhatsappRenewalSession $session, string $text): void
    {
        $name = trim(preg_replace('/\s+/', ' ', $text));

        if (mb_strlen($name) < 3 || !str_contains($name, ' ')) {
            $this->reply($tenant, $phone, 'Tafadhali andika jina lako kamili (jina la kwanza na la ukoo), mfano: Juma Pesa.');
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

        $this->reply($tenant, $phone, "Asante {$name}! Umesajiliwa MoBilling.");
        $this->sendRootMenu($tenant, $client, $phone);
    }

    private function handleSurnameStep(Tenant $tenant, string $phone, WhatsappRenewalSession $session, string $text): void
    {
        $client = Client::withoutGlobalScopes()->find($session->client_id);

        if ($client && $this->surnameMatches($client, $text)) {
            $session->update(['confirmed_at' => now()]);
            $this->sendRootMenu($tenant, $client, $phone);
            return;
        }

        if ($session->attempts >= 2) {
            $session->delete();
            $this->reply($tenant, $phone, 'Samahani, hatujaweza kuthibitisha jina lako. Tafadhali wasiliana nasi kwa msaada.');
            return;
        }

        $session->increment('attempts');
        $this->reply($tenant, $phone, 'Samahani, jina hilo halifanani na tulilonalo. Tafadhali jaribu tena — jina la ukoo (surname) lililosajiliwa MoBilling.');
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

    // ── Root menu ────────────────────────────────────────────────────────

    /**
     * Once verified, a client stays recognised on this phone for 30 days
     * (reset on every reply while idle at the root menu) — surname
     * verification only happens once, not on every message, until they
     * explicitly log out (option 0) or 30 days of inactivity pass.
     */
    private function sendRootMenu(Tenant $tenant, Client $client, string $phone): void
    {
        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'flow' => null, 'state' => null, 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addDays(30)],
        );

        $this->reply($tenant, $phone,
            "Habari {$client->name}! Chagua huduma: "
            . '1) Domain Registration · 2) Domain Renewal · 3) Website Hosting · '
            . '4) Business Email Hosting · 5) Angalia na Lipa Invoice · '
            . '6) WHOIS ya Domain · 7) Angalia kama Domain Inapatikana · '
            . '0) Toka (Logout). Jibu na namba.');
    }

    private function logout(Tenant $tenant, string $phone): void
    {
        WhatsappRenewalSession::where('tenant_id', $tenant->id)->where('phone', $phone)->delete();
        $this->reply($tenant, $phone, 'Umetoka kwenye akaunti yako. Tuma ujumbe wowote kuingia tena.');
    }

    /**
     * Ends a flow's final step by delivering its message and, right after,
     * the root menu again — without this a client who just finished a WHOIS
     * lookup or an order had no visible way back to the menu except
     * re-verifying their surname from scratch (reported live).
     */
    private function finishFlow(Tenant $tenant, Client $client, string $phone, string $message): void
    {
        $this->reply($tenant, $phone, $message);
        $this->sendRootMenu($tenant, $client, $phone);
    }

    private function handleRootStep(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, string $text, RenewalBundleService $bundler): void
    {
        // Renewal picker already active (items populated by sendMenu()): a digit picks one.
        if (!empty($session->items) && preg_match('/^\s*([1-9])\s*$/', $text, $m)) {
            $this->pickAndGenerate($tenant, $client, $phone, $session, (int) $m[1], $bundler);
            return;
        }

        match (true) {
            (bool) preg_match('/^\s*0\s*$/', $text) => $this->logout($tenant, $phone),
            (bool) preg_match('/^\s*1\s*$/', $text) => $this->startOrderDomain($tenant, $client, $phone),
            (bool) preg_match('/^\s*2\s*$/', $text) => $this->sendMenu($tenant, $client, $phone, $bundler),
            (bool) preg_match('/^\s*3\s*$/', $text) => $this->startOrderHosting($tenant, $client, $phone, 'Web Hosting'),
            (bool) preg_match('/^\s*4\s*$/', $text) => $this->startOrderHosting($tenant, $client, $phone, 'Business E-mail'),
            (bool) preg_match('/^\s*5\s*$/', $text) => $this->startPayInvoice($tenant, $client, $phone),
            (bool) preg_match('/^\s*6\s*$/', $text) => $this->startWhois($tenant, $client, $phone),
            (bool) preg_match('/^\s*7\s*$/', $text) => $this->startCheckAvailability($tenant, $client, $phone),
            default => $this->sendRootMenu($tenant, $client, $phone),
        };
    }

    // ── Renewals (existing domains/hosting already owed) ────────────────

    /**
     * Lists every domain the client has — status and expiry — numbering only the
     * ones actually due (billable) so a reply digit stays unambiguous; the rest are
     * shown for information only.
     */
    private function sendMenu(Tenant $tenant, Client $client, string $phone, RenewalBundleService $bundler): void
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
                $lines[] = count($items) . ". {$domain->name} — {$what} inahitaji malipo (deadline {$dueDate})";
            } else {
                $expires = $domain->expires_at?->format('d M Y') ?? '—';
                $lines[] = "• {$domain->name} — inaisha {$expires}, hakuna malipo yanayohitajika sasa";
            }
        }

        if ($domains->isEmpty()) {
            $this->finishFlow($tenant, $client, $phone, "Habari {$client->name}, huna huduma yoyote iliyosajiliwa kwa sasa. Asante!");
            return;
        }

        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'items' => $items, 'flow' => null, 'state' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(30)],
        );

        $this->reply($tenant, $phone,
            "Habari {$client->name}, huduma zako: "
            . implode(' · ', $lines)
            . (!empty($items) ? '. Jibu na namba kulipia huduma inayohitaji malipo.' : '.'));
    }

    /** Picks items[$position-1] out of $session and bills it, or replies with why it can't. */
    private function pickAndGenerate(Tenant $tenant, ?Client $client, string $phone, WhatsappRenewalSession $session, int $position, RenewalBundleService $bundler): void
    {
        $domainId = $session->items[$position - 1] ?? null;
        $client ??= Client::withoutGlobalScopes()->find($session->client_id);
        $session->delete();

        if (!$domainId) {
            $this->replyOrFinish($tenant, $client, $phone, 'Samahani, chaguo hilo silo sahihi. Tafadhali jaribu tena.');
            return;
        }

        $domain = Domain::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($domainId);
        if (!$domain) {
            $this->replyOrFinish($tenant, $client, $phone, 'Samahani, huduma hii haipatikani tena. Tafadhali wasiliana nasi.');
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
            $this->replyOrFinish($tenant, $client, $phone, "Samahani, {$e->getMessage()}");
            return;
        }

        $this->replyWithInvoice($tenant, $phone, $document);
        if ($client) {
            $this->sendRootMenu($tenant, $client, $phone);
        }
    }

    /** finishFlow() when a client is known (returns to the root menu), a plain reply otherwise. */
    private function replyOrFinish(Tenant $tenant, ?Client $client, string $phone, string $message): void
    {
        if ($client) {
            $this->finishFlow($tenant, $client, $phone, $message);
        } else {
            $this->reply($tenant, $phone, $message);
        }
    }

    // ── New domain registration ─────────────────────────────────────────

    private function startOrderDomain(Tenant $tenant, Client $client, string $phone): void
    {
        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'flow' => 'order_domain', 'state' => ['step' => 'ask_name'], 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(10)],
        );

        $this->reply($tenant, $phone, 'Andika jina la domain unalotaka kusajili (mfano: jinalako.co.tz).');
    }

    private function handleOrderDomainStep(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, string $text): void
    {
        $state = $session->state ?? [];
        $step = $state['step'] ?? 'ask_name';

        if ($step === 'ask_name') {
            $name = strtolower(trim($text));
            if (!preg_match('/^[a-z0-9][a-z0-9.-]+\.[a-z.]{2,}$/', $name)) {
                $this->reply($tenant, $phone, 'Samahani, jina hilo halionekani sahihi. Andika kama: jinalako.co.tz');
                return;
            }

            $tld = $this->extractTld($name);
            $pricing = $tld ? DomainTld::priceFor($tenant->id, $tld) : null;

            if (!$pricing || $pricing->is_unmanaged) {
                $this->finishFlow($tenant, $client, $phone, 'Samahani, aina hii ya domain haiwezi kusajiliwa papo hapo kwa sasa. Tafadhali wasiliana nasi.');
                return;
            }

            if (Domain::withoutGlobalScopes()->where('name', $name)->whereNotIn('status', ['cancelled', 'transferred_out'])->exists()) {
                $this->reply($tenant, $phone, "Samahani, {$name} tayari imesajiliwa nasi. Andika jina lingine.");
                return;
            }

            try {
                $availability = app(DomainRegistrarManager::class)->driverFor($tenant->id)->check($name);
            } catch (\Throwable $e) {
                Log::warning('WhatsApp order_domain availability check failed', ['name' => $name, 'error' => $e->getMessage()]);
                $this->finishFlow($tenant, $client, $phone, 'Samahani, imeshindikana kuangalia upatikanaji wa domain hii sasa hivi. Jaribu tena baadaye.');
                return;
            }

            if (!($availability['available'] ?? false)) {
                $this->reply($tenant, $phone, "Samahani, {$name} tayari imesajiliwa na mwenyewe. Andika jina lingine.");
                return;
            }

            $price = (float) $pricing->register_price;
            $session->update(['state' => ['step' => 'confirm', 'domain' => $name, 'price' => $price]]);
            $this->reply($tenant, $phone, "Domain {$name} inapatikana! Bei: TZS " . number_format($price) . ' kwa mwaka 1. Jibu NDIYO kuagiza.');
            return;
        }

        if ($step === 'confirm') {
            if (!preg_match('/^\s*ndiyo\s*$/i', $text)) {
                $this->finishFlow($tenant, $client, $phone, 'Sawa, agizo limesitishwa.');
                return;
            }

            $domain = $state['domain'] ?? null;
            $price = $state['price'] ?? null;

            if (!$domain || !$price) {
                $this->finishFlow($tenant, $client, $phone, 'Samahani, kuna hitilafu. Tafadhali jaribu tena.');
                return;
            }

            try {
                $document = $this->createDomainOrder($tenant, $client, $domain, (float) $price);
            } catch (\Throwable $e) {
                Log::error('WhatsApp order_domain order creation failed', ['domain' => $domain, 'error' => $e->getMessage()]);
                $this->finishFlow($tenant, $client, $phone, 'Samahani, imeshindikana kutengeneza agizo. Tafadhali wasiliana nasi.');
                return;
            }

            $this->replyWithInvoice($tenant, $phone, $document);

            // Continue straight into ordering hosting for the same domain, per request
            // ("agiza domain mpya mpaka ku-provision hosting") — a separate invoice
            // (domain registration and hosting are billed independently throughout this
            // app), but one unbroken conversation. Actual provisioning still only fires
            // once each invoice is actually paid (DocumentObserver / ClientSubscriptionObserver
            // → ProvisionHostingAccount), unchanged — this just removes the need to
            // start a second conversation to get there.
            $session->update(['state' => ['step' => 'offer_hosting', 'domain' => $domain]]);
            $this->reply($tenant, $phone, "Je, unataka pia Website Hosting kwenye {$domain}? Jibu NDIYO kuendelea, au namba nyingine kuruka.");
            return;
        }

        if ($step === 'offer_hosting') {
            if (preg_match('/^\s*ndiyo\s*$/i', $text)) {
                $this->startOrderHosting($tenant, $client, $phone, 'Web Hosting', $state['domain'] ?? null);
                return;
            }

            $this->sendRootMenu($tenant, $client, $phone);
            return;
        }

        $this->finishFlow($tenant, $client, $phone, 'Samahani, kuna hitilafu. Tafadhali jaribu tena.');
    }

    /** Mirrors PortalDomainController::order()'s register path exactly. */
    private function createDomainOrder(Tenant $tenant, Client $client, string $name, float $price): Document
    {
        $registrar = app(DomainRegistrarManager::class);

        return DB::transaction(function () use ($tenant, $client, $name, $price, $registrar) {
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
                'notes' => "Domain registration (WhatsApp order): {$name} (1 year)",
            ]);

            $document->items()->create([
                'item_type' => 'service',
                'description' => "Register domain {$name} — 1 year",
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
                'meta' => [
                    'pending_action' => 'register',
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

    // ── New hosting / business email orders ─────────────────────────────

    /** $prefilledDomain: set when continuing straight from a just-placed domain order — skips ask_domain. */
    private function startOrderHosting(Tenant $tenant, Client $client, string $phone, string $category, ?string $prefilledDomain = null): void
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
            $this->finishFlow($tenant, $client, $phone, 'Samahani, hakuna vifurushi vinavyopatikana kwa sasa. Tafadhali wasiliana nasi.');
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

        $this->reply($tenant, $phone, 'Chagua kifurushi: ' . implode(' · ', $lines) . '. Jibu na namba.');
    }

    private function handleOrderHostingStep(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, string $text): void
    {
        $state = $session->state ?? [];
        $step = $state['step'] ?? 'pick_plan';

        // Picking a number shows that plan's full specs before anything is
        // ordered — the client sees what they'd actually be getting, and can
        // either continue or look at a different numbered option instead.
        if ($step === 'pick_plan' || $step === 'plan_details') {
            if (!preg_match('/^\s*([1-9])\s*$/', $text, $m) || empty($state['plan_ids'][$m[1] - 1])) {
                if ($step === 'plan_details' && preg_match('/^\s*ndiyo\s*$/i', $text)) {
                    $plan = ProductService::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($state['product_service_id'] ?? null);
                    if (!$plan) {
                        $this->finishFlow($tenant, $client, $phone, 'Samahani, kifurushi hicho hakipatikani tena. Tafadhali jaribu tena.');
                        return;
                    }

                    // Already have a domain (continuing straight from a domain order) —
                    // skip straight to confirming instead of asking for it again.
                    if (!empty($state['domain'])) {
                        $session->update(['state' => array_merge($state, ['step' => 'confirm', 'product_service_id' => $plan->id])]);
                        $this->reply($tenant, $phone,
                            "Thibitisha: {$plan->name} — TZS " . number_format((float) $plan->price) . "/{$plan->billing_cycle}, domain: {$state['domain']}. Jibu NDIYO kuagiza.");
                        return;
                    }

                    $session->update(['state' => array_merge($state, ['step' => 'ask_domain', 'product_service_id' => $plan->id])]);
                    $this->reply($tenant, $phone, "Umechagua {$plan->name}. Andika jina la domain la huduma hii (lililopo tayari).");
                    return;
                }

                $this->reply($tenant, $phone, 'Samahani, chagua namba sahihi kutoka kwenye orodha, au jibu NDIYO kuendelea na kifurushi ulichokwishachagua.');
                return;
            }

            $planId = $state['plan_ids'][$m[1] - 1];
            $plan = ProductService::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($planId);
            if (!$plan) {
                $this->finishFlow($tenant, $client, $phone, 'Samahani, kifurushi hicho hakipatikani tena. Tafadhali jaribu tena.');
                return;
            }

            $session->update(['state' => array_merge($state, ['step' => 'plan_details', 'product_service_id' => $plan->id])]);

            $specs = trim((string) $plan->description) !== '' ? str_replace(["\r\n", "\n"], ' · ', trim($plan->description)) : null;
            $this->reply($tenant, $phone,
                "{$plan->name} — TZS " . number_format((float) $plan->price) . "/{$plan->billing_cycle}"
                . ($specs ? ". {$specs}" : '')
                . '. Jibu NDIYO kuagiza hiki, au chagua namba nyingine kutoka kwenye orodha ya awali.');
            return;
        }

        if ($step === 'ask_domain') {
            $name = strtolower(trim($text));
            if (!preg_match('/^[a-z0-9][a-z0-9.-]+\.[a-z.]{2,}$/', $name)) {
                $this->reply($tenant, $phone, 'Samahani, jina hilo halionekani sahihi. Andika kama: jinalako.co.tz');
                return;
            }

            $plan = ProductService::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($state['product_service_id'] ?? null);
            if (!$plan) {
                $this->finishFlow($tenant, $client, $phone, 'Samahani, kuna hitilafu. Tafadhali jaribu tena.');
                return;
            }

            $session->update(['state' => array_merge($state, ['step' => 'confirm', 'domain' => $name])]);
            $this->reply($tenant, $phone,
                "Thibitisha: {$plan->name} — TZS " . number_format((float) $plan->price) . "/{$plan->billing_cycle}, domain: {$name}. Jibu NDIYO kuagiza.");
            return;
        }

        if ($step === 'confirm') {
            if (!preg_match('/^\s*ndiyo\s*$/i', $text)) {
                $this->finishFlow($tenant, $client, $phone, 'Sawa, agizo limesitishwa.');
                return;
            }

            $plan = ProductService::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($state['product_service_id'] ?? null);
            $domain = $state['domain'] ?? null;

            if (!$plan || !$domain) {
                $this->finishFlow($tenant, $client, $phone, 'Samahani, kuna hitilafu. Tafadhali jaribu tena.');
                return;
            }

            try {
                $document = $this->createHostingOrder($tenant, $client, $plan, $domain);
            } catch (\Throwable $e) {
                Log::error('WhatsApp order_hosting order creation failed', ['plan_id' => $plan->id, 'domain' => $domain, 'error' => $e->getMessage()]);
                $this->finishFlow($tenant, $client, $phone, 'Samahani, imeshindikana kutengeneza agizo. Tafadhali wasiliana nasi.');
                return;
            }

            $this->replyWithInvoice($tenant, $phone, $document);
            $this->sendRootMenu($tenant, $client, $phone);
            return;
        }

        $this->finishFlow($tenant, $client, $phone, 'Samahani, kuna hitilafu. Tafadhali jaribu tena.');
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

    private function startPayInvoice(Tenant $tenant, Client $client, string $phone): void
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
            $this->finishFlow($tenant, $client, $phone, "Habari {$client->name}, huna invoice yoyote isiyolipwa kwa sasa. Asante!");
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

        $this->reply($tenant, $phone, 'Invoice zako zisizolipwa: ' . implode(' · ', $lines) . '. Jibu na namba kuchagua.');
    }

    private function handlePayInvoiceStep(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, string $text): void
    {
        $state = $session->state ?? [];
        $step = $state['step'] ?? 'pick_invoice';

        if ($step === 'pick_invoice') {
            if (!preg_match('/^\s*([1-9])\s*$/', $text, $m) || empty($state['doc_ids'][$m[1] - 1])) {
                $this->reply($tenant, $phone, 'Samahani, chagua namba sahihi kutoka kwenye orodha.');
                return;
            }

            $docId = $state['doc_ids'][$m[1] - 1];
            $doc = Document::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($docId);
            if (!$doc) {
                $this->finishFlow($tenant, $client, $phone, 'Samahani, invoice hiyo haipatikani tena. Tafadhali jaribu tena.');
                return;
            }

            $session->update(['state' => ['step' => 'choose_method', 'document_id' => $doc->id]]);
            $this->reply($tenant, $phone,
                "Invoice {$doc->document_number} — TZS " . number_format((float) $doc->balance_due) . '. Chagua njia ya kulipa: 1) Online (Pesapal) · 2) Maelezo ya kulipa (Benki/Lipa Namba). Jibu na namba.');
            return;
        }

        if ($step === 'choose_method') {
            $doc = Document::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($state['document_id'] ?? null);

            if (!$doc) {
                $this->finishFlow($tenant, $client, $phone, 'Samahani, invoice hiyo haipatikani tena. Tafadhali jaribu tena.');
                return;
            }

            if (preg_match('/^\s*1\s*$/', $text)) {
                if (!$tenant->pesapal_enabled || !$tenant->pesapal_consumer_key) {
                    $this->reply($tenant, $phone, 'Samahani, malipo ya online hayapatikani kwa sasa. Tuma tena na uchague namba 2 kwa maelezo ya benki.');
                    return;
                }
                try {
                    $redirectUrl = $this->pesapalCheckout($tenant, $doc);
                    $this->finishFlow($tenant, $client, $phone, "Lipa hapa: {$redirectUrl}");
                } catch (\Throwable $e) {
                    Log::warning('WhatsApp pay_invoice Pesapal checkout failed', ['document_id' => $doc->id, 'error' => $e->getMessage()]);
                    $this->finishFlow($tenant, $client, $phone, 'Samahani, imeshindikana kutengeneza link ya kulipa. Tafadhali jaribu tena baadaye.');
                }
                return;
            }

            if (preg_match('/^\s*2\s*$/', $text)) {
                $this->finishFlow($tenant, $client, $phone, $this->paymentDetailsText($tenant));
                return;
            }

            $this->finishFlow($tenant, $client, $phone, 'Samahani, sikuelewa.');
            return;
        }

        $this->finishFlow($tenant, $client, $phone, 'Samahani, kuna hitilafu. Tafadhali jaribu tena.');
    }

    private function paymentDetailsText(Tenant $tenant): string
    {
        $bank = trim(implode(' · ', array_filter([
            $tenant->bank_name ? "Benki: {$tenant->bank_name}" : null,
            $tenant->bank_account_name ? "Jina: {$tenant->bank_account_name}" : null,
            $tenant->bank_account_number ? "Namba: {$tenant->bank_account_number}" : null,
            $tenant->payment_instructions ?: null,
        ])));

        return $bank !== '' ? "Lipa kupitia: {$bank}" : 'Tafadhali wasiliana nasi kwa maelezo ya kulipa.';
    }

    // ── WHOIS lookup ─────────────────────────────────────────────────────

    private function startWhois(Tenant $tenant, Client $client, string $phone): void
    {
        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'flow' => 'whois', 'state' => ['step' => 'ask_name'], 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(10)],
        );

        $this->reply($tenant, $phone, 'Andika jina la domain (.tz) unalotaka kuangalia taarifa zake (mfano: jinalako.co.tz).');
    }

    private function handleWhoisStep(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, string $text): void
    {
        $whois = app(TznicWhoisService::class);
        $name = $whois->normalise(strtolower(trim($text)));

        if (!str_ends_with($name, '.tz') || substr_count($name, '.') < 1) {
            $this->reply($tenant, $phone, 'Samahani, andika jina la domain la .tz, mfano: jinalako.co.tz');
            return;
        }

        try {
            $info = $whois->lookup($name);
        } catch (\Throwable $e) {
            Log::warning('WhatsApp WHOIS lookup failed', ['name' => $name, 'error' => $e->getMessage()]);
            $this->finishFlow($tenant, $client, $phone, 'Samahani, imeshindikana kupata taarifa za domain hii sasa hivi. Jaribu tena baadaye.');
            return;
        }

        if (!($info['found'] ?? false)) {
            $this->finishFlow($tenant, $client, $phone, "Domain {$name} haijasajiliwa.");
            return;
        }

        $this->finishFlow($tenant, $client, $phone, implode(' · ', array_filter([
            "Domain: {$name}",
            $info['registrar'] ? "Msajili: {$info['registrar']}" : null,
            $info['registered'] ? "Ilisajiliwa: {$info['registered']}" : null,
            $info['expire'] ? "Inaisha: {$info['expire']}" : null,
            !empty($info['nameservers']) ? 'Nameservers: ' . implode(', ', $info['nameservers']) : null,
        ])));
    }

    // ── Standalone availability check ───────────────────────────────────

    private function startCheckAvailability(Tenant $tenant, Client $client, string $phone): void
    {
        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'flow' => 'check_availability', 'state' => ['step' => 'ask_name'], 'items' => null, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(10)],
        );

        $this->reply($tenant, $phone, 'Andika jina la domain unalotaka kuangalia kama linapatikana (mfano: jinalako.co.tz).');
    }

    private function handleCheckAvailabilityStep(Tenant $tenant, Client $client, string $phone, WhatsappRenewalSession $session, string $text): void
    {
        $name = strtolower(trim($text));
        if (!preg_match('/^[a-z0-9][a-z0-9.-]+\.[a-z.]{2,}$/', $name)) {
            $this->reply($tenant, $phone, 'Samahani, jina hilo halionekani sahihi. Andika kama: jinalako.co.tz');
            return;
        }

        $tld = $this->extractTld($name);
        $pricing = $tld ? DomainTld::priceFor($tenant->id, $tld) : null;

        if (!$pricing || $pricing->is_unmanaged) {
            $this->finishFlow($tenant, $client, $phone, 'Samahani, hatuwezi kuangalia aina hii ya domain papo hapo. Tafadhali wasiliana nasi.');
            return;
        }

        try {
            $availability = app(DomainRegistrarManager::class)->driverFor($tenant->id)->check($name);
        } catch (\Throwable $e) {
            Log::warning('WhatsApp check_availability failed', ['name' => $name, 'error' => $e->getMessage()]);
            $this->finishFlow($tenant, $client, $phone, 'Samahani, imeshindikana kuangalia domain hii sasa hivi. Jaribu tena baadaye.');
            return;
        }

        if ($availability['available'] ?? false) {
            $price = number_format((float) $pricing->register_price);
            $this->finishFlow($tenant, $client, $phone, "Domain {$name} INAPATIKANA! Bei ya kusajili: TZS {$price}/mwaka. Chagua namba 1 kuagiza.");
        } else {
            $this->finishFlow($tenant, $client, $phone, "Domain {$name} tayari limesajiliwa — halipatikani.");
        }
    }

    // ── Payment ──────────────────────────────────────────────────────────

    private function replyWithInvoice(Tenant $tenant, string $phone, Document $document): void
    {
        $total = number_format((float) $document->total);

        if ($tenant->pesapal_enabled && $tenant->pesapal_consumer_key) {
            try {
                $redirectUrl = $this->pesapalCheckout($tenant, $document);
                $this->reply($tenant, $phone,
                    "Invoice {$document->document_number} — TZS {$total}. Lipa hapa: {$redirectUrl}");
                return;
            } catch (\Throwable $e) {
                Log::warning('WhatsApp Pesapal checkout failed', ['document_id' => $document->id, 'error' => $e->getMessage()]);
                // fall through to bank details below
            }
        }

        $this->reply($tenant, $phone,
            "Invoice {$document->document_number} — TZS {$total} imetengenezwa. " . $this->paymentDetailsText($tenant));
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
}
