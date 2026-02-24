<?php

namespace App\Services;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class PesapalService
{
    private string $baseUrl;

    public function __construct()
    {
        $this->baseUrl = config('pesapal.sandbox')
            ? config('pesapal.sandbox_url')
            : config('pesapal.production_url');
    }

    public function getToken(): string
    {
        return Cache::remember('pesapal_token', config('pesapal.token_cache_ttl', 240), function () {
            $response = Http::post("{$this->baseUrl}/api/Auth/RequestToken", [
                'consumer_key' => config('pesapal.consumer_key'),
                'consumer_secret' => config('pesapal.consumer_secret'),
            ]);

            if (!$response->successful()) {
                Log::error('Pesapal token request failed', ['body' => $response->body()]);
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

    public function submitOrder(string $merchantRef, float $amount, string $description, array $billing): array
    {
        $payload = [
            'id' => $merchantRef,
            'currency' => config('pesapal.currency', 'TZS'),
            'amount' => $amount,
            'description' => $description,
            'callback_url' => config('pesapal.callback_url'),
            'notification_id' => config('pesapal.ipn_id'),
            'billing_address' => [
                'email_address' => $billing['email'] ?? '',
                'phone_number' => $billing['phone'] ?? '',
                'first_name' => $billing['first_name'] ?? '',
                'last_name' => $billing['last_name'] ?? '',
            ],
        ];

        Log::info('Pesapal: submitting order', ['merchant_ref' => $merchantRef, 'amount' => $amount]);

        $response = Http::withToken($this->getToken())
            ->post("{$this->baseUrl}/api/Transactions/SubmitOrderRequest", $payload);

        if (!$response->successful()) {
            Log::error('Pesapal order submission failed', ['body' => $response->body()]);
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
            Log::error('Pesapal status check failed', [
                'order_tracking_id' => $orderTrackingId,
                'body' => $response->body(),
            ]);
            throw new \RuntimeException('Failed to get transaction status: ' . $response->body());
        }

        return $response->json();
    }
}
