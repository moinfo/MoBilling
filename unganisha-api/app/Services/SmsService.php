<?php

namespace App\Services;

use App\Models\Tenant;
use Illuminate\Support\Facades\Http;

class SmsService
{
    private string $baseUrl;
    private int $timeout;

    public function __construct()
    {
        $this->baseUrl = config('smsgateway.base_url');
        $this->timeout = config('smsgateway.timeout');
    }

    /**
     * Send an SMS via the tenant's gateway account.
     */
    public function send(Tenant $tenant, string $recipient, string $message): array
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
                'Content-Type' => 'application/json',
            ])
            ->post('/api/sms/v1/text/single', [
                'from' => $tenant->sender_id,
                'text' => $message,
                'to' => $recipient,
            ]);

        if (!$response->successful()) {
            throw new \RuntimeException(
                'SMS send failed: ' . ($response->json('message') ?? $response->body())
            );
        }

        return $response->json();
    }

    /**
     * Send an OTP SMS using tenant credentials, falling back to platform master credentials.
     */
    public function sendOtp(string $recipient, string $message, ?Tenant $tenant = null): array
    {
        // Try tenant credentials first
        if ($tenant && $tenant->sms_enabled && $tenant->sms_authorization) {
            return $this->send($tenant, $recipient, $message);
        }

        // Fall back to platform master credentials
        $masterAuth = config('smsgateway.master_authorization');
        if (!$masterAuth) {
            throw new \RuntimeException('No SMS credentials available.');
        }

        $response = Http::baseUrl($this->baseUrl)
            ->timeout($this->timeout)
            ->withHeaders([
                'Authorization' => str_starts_with($masterAuth, 'Basic ') ? $masterAuth : 'Basic ' . $masterAuth,
                'Accept' => 'application/json',
                'Content-Type' => 'application/json',
            ])
            ->post('/api/sms/v1/text/single', [
                'from' => $tenant?->sender_id ?? 'MoBilling',
                'text' => $message,
                'to' => $recipient,
            ]);

        if (!$response->successful()) {
            throw new \RuntimeException(
                'SMS send failed: ' . ($response->json('message') ?? $response->body())
            );
        }

        return $response->json();
    }
}
