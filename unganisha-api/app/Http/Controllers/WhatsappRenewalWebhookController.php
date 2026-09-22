<?php

namespace App\Http\Controllers;

use App\Helpers\PhoneHelper;
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
 * MoSMS forwards a client's bare "1" reply to a domain-expiry WhatsApp
 * reminder here (see MoSMS's WhatsAppWebhookController::handleMobillingRenewalReply()).
 * MoSMS only tells us which of its own tenants + which phone replied — the
 * actual domain is looked up from whatsapp_renewal_sessions, written when
 * the reminder was sent (SendDomainExpiryReminders).
 *
 * Public, no Laravel auth — guarded by a shared secret, mirroring MoSMS's
 * own mopos debt-confirmation callback.
 */
class WhatsappRenewalWebhookController extends Controller
{
    public function confirm(Request $request, RenewalBundleService $bundler)
    {
        $request->validate([
            'secret' => 'required|string',
            'mosms_tenant_id' => 'required',
            'phone' => 'required|string',
        ]);

        if (!hash_equals((string) config('services.mosms.inbound_webhook_secret'), (string) $request->secret)) {
            return response()->json(['message' => 'Forbidden'], 403);
        }

        $account = MosmsAccount::withoutGlobalScopes()
            ->where('mosms_tenant_id', $request->mosms_tenant_id)
            ->first();

        if (!$account) {
            Log::warning('WhatsApp renewal reply: no MosmsAccount for mosms_tenant_id', ['mosms_tenant_id' => $request->mosms_tenant_id]);
            return response('OK', 200);
        }

        $phone = PhoneHelper::normalize($request->phone);

        $session = WhatsappRenewalSession::withoutGlobalScopes()
            ->where('tenant_id', $account->tenant_id)
            ->where('phone', $phone)
            ->first();

        $tenant = Tenant::withoutGlobalScopes()->find($account->tenant_id);
        if (!$tenant) {
            return response('OK', 200);
        }

        if (!$session || $session->isExpired()) {
            $this->reply($tenant, $phone, 'Samahani, muda wa kujibu umepita. Tafadhali wasiliana nasi au ingia kwenye client portal kufanya renewal.');
            return response('OK', 200);
        }

        $domain = Domain::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->find($session->domain_id);

        $session->delete();

        if (!$domain) {
            $this->reply($tenant, $phone, 'Samahani, huduma hii haipatikani tena. Tafadhali wasiliana nasi.');
            return response('OK', 200);
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
            return response('OK', 200);
        }

        $this->replyWithInvoice($tenant, $phone, $document);

        return response('OK', 200);
    }

    private function replyWithInvoice(Tenant $tenant, string $phone, \App\Models\Document $document): void
    {
        $total = number_format((float) $document->total);

        if ($tenant->pesapal_enabled && $tenant->pesapal_consumer_key) {
            try {
                $redirectUrl = $this->pesapalCheckout($tenant, $document);
                $this->reply($tenant, $phone,
                    "Invoice {$document->document_number} — TZS {$total}.\n\nLipa hapa: {$redirectUrl}");
                return;
            } catch (\Throwable $e) {
                Log::warning('WhatsApp renewal Pesapal checkout failed', ['document_id' => $document->id, 'error' => $e->getMessage()]);
                // fall through to bank details below
            }
        }

        $bank = trim(implode("\n", array_filter([
            $tenant->bank_name ? "Benki: {$tenant->bank_name}" : null,
            $tenant->bank_account_name ? "Jina: {$tenant->bank_account_name}" : null,
            $tenant->bank_account_number ? "Namba: {$tenant->bank_account_number}" : null,
        ])));

        $this->reply($tenant, $phone,
            "Invoice {$document->document_number} — TZS {$total} imetengenezwa."
            . ($bank !== '' ? "\n\nLipa kupitia:\n{$bank}" : "\n\nTafadhali wasiliana nasi kulipa."));
    }

    private function pesapalCheckout(Tenant $tenant, \App\Models\Document $document): string
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

    private function reply(Tenant $tenant, string $phone, string $message): void
    {
        try {
            app(WhatsAppService::class)->sendText($tenant, $phone, $message);
        } catch (\Throwable $e) {
            Log::warning('WhatsApp renewal reply send failed', ['tenant_id' => $tenant->id, 'phone' => $phone, 'error' => $e->getMessage()]);
        }
    }
}
