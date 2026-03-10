<?php

namespace App\Services;

use App\Models\Tenant;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class TenantPesapalService
{
    private string $baseUrl;
    private Tenant $tenant;

    public function __construct(Tenant $tenant)
    {
        $this->tenant = $tenant;
        $this->baseUrl = $tenant->pesapal_sandbox
            ? config('pesapal.sandbox_url')
            : config('pesapal.production_url');
    }

    public function getToken(): string
    {
        $cacheKey = "pesapal_token_tenant_{$this->tenant->id}";

        return Cache::remember($cacheKey, 240, function () {
            $response = Http::post("{$this->baseUrl}/api/Auth/RequestToken", [
                'consumer_key' => $this->tenant->pesapal_consumer_key,
                'consumer_secret' => $this->tenant->pesapal_consumer_secret,
            ]);

            if (!$response->successful()) {
                Log::error('Tenant Pesapal token failed', [
                    'tenant_id' => $this->tenant->id,
                    'body' => $response->body(),
                ]);
                throw new \RuntimeException('Failed to obtain Pesapal token: ' . $response->body());
            }

            return $response->json('token');
        });
    }

    public function registerIpn(string $url, string $type = 'GET'): array
    {
        $response = Http::withToken($this->getToken())
            ->post("{$this->baseUrl}/api/URLSetup/RegisterIPN", [
                'url' => $url,
                'ipn_notification_type' => $type,
            ]);

        if (!$response->successful()) {
            throw new \RuntimeException('Failed to register IPN: ' . $response->body());
        }

        return $response->json();
    }

    public function submitOrder(string $merchantRef, float $amount, string $description, array $billing, string $callbackUrl): array
    {
        $payload = [
            'id' => $merchantRef,
            'currency' => $this->tenant->currency ?? 'TZS',
            'amount' => $amount,
            'description' => $description,
            'callback_url' => $callbackUrl,
            'notification_id' => $this->tenant->pesapal_ipn_id,
            'billing_address' => [
                'email_address' => $billing['email'] ?? '',
                'phone_number' => $billing['phone'] ?? '',
                'first_name' => $billing['first_name'] ?? '',
                'last_name' => $billing['last_name'] ?? '',
            ],
        ];

        Log::info('Tenant Pesapal: submitting order', [
            'tenant_id' => $this->tenant->id,
            'merchant_ref' => $merchantRef,
            'amount' => $amount,
        ]);

        $response = Http::withToken($this->getToken())
            ->post("{$this->baseUrl}/api/Transactions/SubmitOrderRequest", $payload);

        if (!$response->successful()) {
            Log::error('Tenant Pesapal order failed', [
                'tenant_id' => $this->tenant->id,
                'body' => $response->body(),
            ]);
            throw new \RuntimeException('Failed to submit Pesapal order: ' . $response->body());
        }

        return $response->json();
    }

    public function getTransactionStatus(string $orderTrackingId): array
    {
        $response = Http::withToken($this->getToken())
            ->get("{$this->baseUrl}/api/Transactions/GetTransactionStatus", [
                'orderTrackingId' => $orderTrackingId,
            ]);

        if (!$response->successful()) {
            Log::error('Tenant Pesapal status check failed', [
                'tenant_id' => $this->tenant->id,
                'order_tracking_id' => $orderTrackingId,
                'body' => $response->body(),
            ]);
            throw new \RuntimeException('Failed to get transaction status: ' . $response->body());
        }

        return $response->json();
    }
}
