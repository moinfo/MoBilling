<?php

namespace App\Services;

use App\Models\Tenant;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class WhatsAppService
{
    private string $apiVersion;
    private int $timeout;

    public function __construct()
    {
        $this->apiVersion = config('whatsapp.api_version', 'v18.0');
        $this->timeout = config('whatsapp.timeout', 30);
    }

    /**
     * Send a plain text message via WhatsApp Business API.
     * Best for session-based (within 24h) replies.
     */
    public function sendText(Tenant $tenant, string $recipient, string $message): array
    {
        $this->validateCredentials($tenant);

        $response = Http::baseUrl("https://graph.facebook.com/{$this->apiVersion}")
            ->timeout($this->timeout)
            ->withToken($tenant->whatsapp_access_token)
            ->post("/{$tenant->whatsapp_phone_number_id}/messages", [
                'messaging_product' => 'whatsapp',
                'to' => $this->formatPhone($recipient),
                'type' => 'text',
                'text' => ['body' => $message],
            ]);

        if (!$response->successful()) {
            $error = $response->json('error.message') ?? $response->body();
            Log::error('WhatsApp send failed', [
                'tenant_id' => $tenant->id,
                'recipient' => $recipient,
                'error' => $error,
            ]);
            throw new \RuntimeException("WhatsApp send failed: {$error}");
        }

        return $response->json();
    }

    /**
     * Send a template message via WhatsApp Business API.
     * Required for business-initiated messages (outside 24h window).
     */
    public function sendTemplate(
        Tenant $tenant,
        string $recipient,
        string $templateName,
        array $parameters = [],
        string $language = 'en'
    ): array {
        $this->validateCredentials($tenant);

        $components = [];
        if (!empty($parameters)) {
            $components[] = [
                'type' => 'body',
                'parameters' => array_map(fn ($p) => [
                    'type' => 'text',
                    'text' => (string) $p,
                ], $parameters),
            ];
        }

        $payload = [
            'messaging_product' => 'whatsapp',
            'to' => $this->formatPhone($recipient),
            'type' => 'template',
            'template' => [
                'name' => $templateName,
                'language' => ['code' => $language],
            ],
        ];

        if (!empty($components)) {
            $payload['template']['components'] = $components;
        }

        $response = Http::baseUrl("https://graph.facebook.com/{$this->apiVersion}")
            ->timeout($this->timeout)
            ->withToken($tenant->whatsapp_access_token)
            ->post("/{$tenant->whatsapp_phone_number_id}/messages", $payload);

        if (!$response->successful()) {
            $error = $response->json('error.message') ?? $response->body();
            Log::error('WhatsApp template send failed', [
                'tenant_id' => $tenant->id,
                'recipient' => $recipient,
                'template' => $templateName,
                'error' => $error,
            ]);
            throw new \RuntimeException("WhatsApp template send failed: {$error}");
        }

        return $response->json();
    }

    private function validateCredentials(Tenant $tenant): void
    {
        if (!$tenant->whatsapp_phone_number_id || !$tenant->whatsapp_access_token) {
            throw new \RuntimeException('Tenant has no WhatsApp credentials configured.');
        }
    }

    /**
     * Format phone number: strip leading + and ensure country code.
     */
    private function formatPhone(string $phone): string
    {
        $phone = preg_replace('/[^0-9]/', '', $phone);

        // Tanzania: if starts with 0, replace with 255
        if (str_starts_with($phone, '0') && strlen($phone) <= 10) {
            $phone = '255' . substr($phone, 1);
        }

        return $phone;
    }
}
