<?php

namespace App\Http\Controllers;

use App\Helpers\PhoneHelper;
use App\Models\Client;
use App\Models\Document;
use App\Models\Domain;
use App\Models\HostingAccount;
use App\Models\MosmsAccount;
use App\Models\PesapalInvoicePayment;
use App\Models\Tenant;
use App\Models\WhatsappRenewalSession;
use App\Services\Hosting\RenewalBundleService;
use App\Services\TenantPesapalService;
use App\Services\WhatsAppService;
use Illuminate\Http\Request;
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
 *    "what can I do" self-service catch-all.
 * Both end up picking an item out of the same whatsapp_renewal_sessions
 * `items` list (an ordered array of Domain ids) and, once picked, billing
 * it the same way via RenewalBundleService.
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

        $this->pickAndGenerate($tenant, $phone, $session, 1, $bundler);

        return response('OK', 200);
    }

    /**
     * Catch-all: any other message from a phone MoSMS believes belongs to
     * this tenant's conversation. If there's an active menu session and the
     * reply is a valid pick (1-9), bill that item. Otherwise (fresh contact,
     * expired session, or unrecognised text) look the phone up as a client
     * and (re)send the menu of what they can currently self-serve.
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

        if ($session && !$session->isExpired()) {
            // Already confirmed + menu sent: a digit 1-9 picks an item.
            if ($session->confirmed_at && !empty($session->items) && preg_match('/^\s*([1-9])\s*$/', $text, $m)) {
                $this->pickAndGenerate($tenant, $phone, $session, (int) $m[1], $bundler);
                return response('OK', 200);
            }

            // Awaiting "yes, this is my account" — anything else re-asks rather than
            // silently proceeding, since the phone match alone isn't proof of identity.
            if (!$session->confirmed_at) {
                if (preg_match('/^\s*(ndiyo|ndio|yes|sawa)\s*$/i', $text)) {
                    $client = Client::withoutGlobalScopes()->find($session->client_id);
                    if ($client) {
                        $this->sendMenu($tenant, $client, $phone, $bundler);
                        return response('OK', 200);
                    }
                }

                $session->delete();
                $this->reply($tenant, $phone, 'Sawa, tukikuhitaji tutakuarifu. Kama ulitaka kujihudumia, tuma ujumbe wowote kuanza tena.');
                return response('OK', 200);
            }
        }

        $client = Client::withoutGlobalScopes()->where('tenant_id', $tenant->id);
        $client = PhoneHelper::wherePhone($client, 'phone', $phone)->first();

        if (!$client) {
            // Most-recent-sender attribution is a heuristic, not a guarantee — a phone that
            // isn't actually a Moinfotech client stays silent rather than getting a stray reply.
            Log::info('WhatsApp menu: phone not matched to a client', ['tenant_id' => $tenant->id, 'phone' => $phone]);
            return response('OK', 200);
        }

        // Identity is not proven by the phone match alone (it's a heuristic on the shared
        // MoSMS number) — ask before showing any account details, exactly as requested.
        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'items' => null, 'confirmed_at' => null, 'expires_at' => now()->addMinutes(10)],
        );

        $this->reply($tenant, $phone,
            "Tumekuta akaunti ya {$client->name} iliyosajiliwa MoBilling. Je, hii ni wewe? Jibu NDIYO kuendelea.");

        return response('OK', 200);
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

    /** Builds and sends the numbered list of domains this client can currently self-serve on. */
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
                ]));
            } catch (\Throwable $e) {
                continue;
            }

            if (empty($billable)) {
                continue;
            }

            $items[] = $domain->id;
            $what = implode(' + ', array_unique(array_map(fn ($s) => $s->productService->category, $billable)));
            $lines[] = count($items) . ". {$domain->name} — {$what} renewal";

            if (count($items) >= 9) {
                break;
            }
        }

        if (empty($items)) {
            WhatsappRenewalSession::where('tenant_id', $tenant->id)->where('phone', $phone)->delete();
            $this->reply($tenant, $phone, "Habari {$client->name}, kwa sasa huna huduma inayohitaji malipo. Asante!");
            return;
        }

        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $tenant->id, 'phone' => $phone],
            ['client_id' => $client->id, 'items' => $items, 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(30)],
        );

        $this->reply($tenant, $phone,
            "Habari {$client->name}, huduma unazoweza kujihudumia: "
            . implode(' · ', $lines)
            . '. Jibu na namba kuchagua.');
    }

    /** Picks items[$position-1] out of $session and bills it, or replies with why it can't. */
    private function pickAndGenerate(Tenant $tenant, string $phone, WhatsappRenewalSession $session, int $position, RenewalBundleService $bundler): void
    {
        $domainId = $session->items[$position - 1] ?? null;
        $session->delete();

        if (!$domainId) {
            $this->reply($tenant, $phone, 'Samahani, chaguo hilo silo sahihi. Tafadhali jaribu tena.');
            return;
        }

        $domain = Domain::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($domainId);
        if (!$domain) {
            $this->reply($tenant, $phone, 'Samahani, huduma hii haipatikani tena. Tafadhali wasiliana nasi.');
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
            ]));
        } catch (\Throwable $e) {
            $this->reply($tenant, $phone, "Samahani, {$e->getMessage()}");
            return;
        }

        $this->replyWithInvoice($tenant, $phone, $document);
    }

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
                Log::warning('WhatsApp renewal Pesapal checkout failed', ['document_id' => $document->id, 'error' => $e->getMessage()]);
                // fall through to bank details below
            }
        }

        $bank = trim(implode(' · ', array_filter([
            $tenant->bank_name ? "Benki: {$tenant->bank_name}" : null,
            $tenant->bank_account_name ? "Jina: {$tenant->bank_account_name}" : null,
            $tenant->bank_account_number ? "Namba: {$tenant->bank_account_number}" : null,
        ])));

        $this->reply($tenant, $phone,
            "Invoice {$document->document_number} — TZS {$total} imetengenezwa."
            . ($bank !== '' ? " Lipa kupitia: {$bank}" : ' Tafadhali wasiliana nasi kulipa.'));
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
     * Always a reply to something this phone just messaged (confirm/menu/invoice text),
     * so the free-form session path applies — no template wrapper copy.
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
