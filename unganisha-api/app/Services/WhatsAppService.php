<?php

namespace App\Services;

use App\Models\Tenant;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class WhatsAppService
{
    /** AUTHENTICATION templates whose copy-code button carries the first variable. */
    private const AUTH_TEMPLATES = ['otp_code'];

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
        // Dual-mode: tenants without their own Meta credentials send through
        // their linked MoSMS account instead (MoSMS fans out to Meta).
        if ($this->useMosms($tenant)) {
            return app(MosmsService::class)->sendText($tenant, $recipient, $message);
        }

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
        string $language = 'en',
        ?string $buttonUrlParam = null
    ): array {
        if ($this->useMosms($tenant)) {
            return app(MosmsService::class)->sendTemplate($tenant, $recipient, $templateName, $parameters, $language, $buttonUrlParam);
        }

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
        if ($buttonUrlParam !== null) {
            $components[] = [
                'type' => 'button',
                'sub_type' => 'url',
                'index' => '0',
                'parameters' => [['type' => 'text', 'text' => $buttonUrlParam]],
            ];
        }
        if (in_array($templateName, self::AUTH_TEMPLATES, true) && !empty($parameters)) {
            $components[] = [
                'type' => 'button',
                'sub_type' => 'url',
                'index' => '0',
                'parameters' => [['type' => 'text', 'text' => (string) $parameters[0]]],
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

    /** True when the tenant has no direct Meta credentials but is linked to MoSMS. */
    private function useMosms(Tenant $tenant): bool
    {
        if ($tenant->whatsapp_phone_number_id && $tenant->whatsapp_access_token) {
            return false;   // own Meta number wins — nothing changes for them
        }
        return app(MosmsService::class)->isLinked($tenant);
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
