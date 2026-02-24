<?php

namespace App\Services;

use App\Models\Tenant;
use Illuminate\Support\Facades\Http;

class ResellerService
{
    private string $baseUrl;
    private string $masterAuth;
    private int $timeout;

    public function __construct()
    {
        $this->baseUrl = config('smsgateway.base_url');
        $this->masterAuth = config('smsgateway.master_authorization');
        $this->timeout = config('smsgateway.timeout');
    }

    public function createSubCustomer(array $data): array
    {
        $nameParts = explode(' ', $data['name'], 2);

        $response = Http::baseUrl($this->baseUrl)
            ->timeout($this->timeout)
            ->withHeaders($this->masterHeaders())
            ->post('/api/reseller/v1/sub_customer/create', [
                'first_name' => $nameParts[0],
                'last_name' => $nameParts[1] ?? $nameParts[0],
                'username' => $data['gateway_username'],
                'email' => $data['gateway_email'],
                'phone_number' => $data['phone_number'] ?? '',
                'account_type' => 'Sub Customer (Reseller)',
                'sms_price' => $data['sms_price'] ?? 0,
            ]);

        if (!$response->successful()) {
            $body = $response->json();
            $message = $body['message'] ?? $response->body();

            if (!empty($body['errors'])) {
                $details = collect($body['errors'])
                    ->map(fn($msgs, $field) => "$field: " . implode(', ', (array) $msgs))
                    ->implode('; ');
                $message = $details;
            }

            throw new \RuntimeException("Gateway: $message");
        }

        return $response->json();
    }

    public function recharge(string $email, int $smsCount): array
    {
        return $this->callReseller('/api/reseller/v1/sub_customer/recharge', $email, $smsCount);
    }

    public function deduct(string $email, int $smsCount): array
    {
        return $this->callReseller('/api/reseller/v1/sub_customer/deduct', $email, $smsCount);
    }

    public function getBalance(Tenant $tenant): array
    {
        if (!$tenant->sms_authorization) {
            throw new \RuntimeException('Tenant has no SMS authorization configured.');
        }

        $auth = $tenant->sms_authorization;

        $response = Http::baseUrl($this->baseUrl)
            ->timeout($this->timeout)
            ->withHeaders([
                'Authorization' => str_starts_with($auth, 'Basic ') ? $auth : 'Basic ' . $auth,
                'Accept' => 'application/json',
            ])
            ->get('/api/sms/v1/balance');

        if (!$response->successful()) {
            throw new \RuntimeException(
                'Gateway error: ' . ($response->json('message') ?? $response->body())
            );
        }

        return $response->json();
    }

    public function getMasterBalance(): array
    {
        $response = Http::baseUrl($this->baseUrl)
            ->timeout($this->timeout)
            ->withHeaders($this->masterHeaders())
            ->get('/api/sms/v1/balance');

        if (!$response->successful()) {
            throw new \RuntimeException(
                'Gateway error: ' . ($response->json('message') ?? $response->body())
            );
        }

        return $response->json();
    }

    private function callReseller(string $endpoint, string $email, int $smsCount): array
    {
        $response = Http::baseUrl($this->baseUrl)
            ->timeout($this->timeout)
            ->withHeaders($this->masterHeaders())
            ->post($endpoint, [
                'email' => $email,
                'smscount' => $smsCount,
            ]);

        if (!$response->successful()) {
            throw new \RuntimeException(
                'Gateway error: ' . ($response->json('message') ?? $response->body())
            );
        }

        return $response->json();
    }

    private function masterHeaders(): array
    {
        $auth = $this->masterAuth;

        return [
            'Authorization' => str_starts_with($auth, 'Basic ') ? $auth : 'Basic ' . $auth,
            'Accept' => 'application/json',
            'Content-Type' => 'application/json',
        ];
    }
}
