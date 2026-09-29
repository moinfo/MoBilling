<?php

namespace App\Services;

use App\Models\Tenant;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class WhatsAppService
{
    /** AUTHENTICATION templates whose copy-code button carries the first variable. */
    private const AUTH_TEMPLATES = ['otp_code'];

    /** Backoff (seconds) after each 429 from Meta before retrying — same idea as MosmsService::request(). */
    private const RATE_LIMIT_BACKOFF_SECONDS = [2, 5];

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

        $response = $this->postWithRateLimitRetry($tenant, "/{$tenant->whatsapp_phone_number_id}/messages", [
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
     * Free-form reply within an open 24h session — a MoSMS-routed tenant gets this
     * without the custom_message wrapper's fixed copy (unlike sendText(), which is
     * always template-based for MoSMS-routed tenants). Only valid as a reply to
     * something the recipient messaged first; a direct-Meta tenant's sendText() is
     * already genuinely free-form, so this is just an alias for them.
     */
    public function sendSessionText(Tenant $tenant, string $recipient, string $message): array
    {
        if ($this->useMosms($tenant)) {
            return app(MosmsService::class)->sendSessionText($tenant, $recipient, $message);
        }

        return $this->sendText($tenant, $recipient, $message);
    }

    /**
     * Free-form "Call-To-Action URL" button (24h session window only, same rule as
     * sendSessionText()) — Meta renders a proper button and opens the URL in WhatsApp's own
     * in-app browser, instead of a plain-text message with a pasted link the customer has to
     * tap-and-hold to open. Used for payment links so checkout stays inside WhatsApp.
     */
    public function sendCtaUrlSession(Tenant $tenant, string $recipient, string $text, string $buttonText, string $url): array
    {
        if ($this->useMosms($tenant)) {
            return app(MosmsService::class)->sendCtaUrl($tenant, $recipient, $text, $buttonText, $url);
        }

        $this->validateCredentials($tenant);

        $response = $this->postWithRateLimitRetry($tenant, "/{$tenant->whatsapp_phone_number_id}/messages", [
            'messaging_product' => 'whatsapp',
            'recipient_type' => 'individual',
            'to' => $this->formatPhone($recipient),
            'type' => 'interactive',
            'interactive' => [
                'type' => 'cta_url',
                'body' => ['text' => $text],
                'action' => [
                    'name' => 'cta_url',
                    'parameters' => ['display_text' => $buttonText, 'url' => $url],
                ],
            ],
        ]);

        if (!$response->successful()) {
            $error = $response->json('error.message') ?? $response->body();
            Log::error('WhatsApp CTA-URL send failed', [
                'tenant_id' => $tenant->id,
                'recipient' => $recipient,
                'error' => $error,
            ]);
            throw new \RuntimeException("WhatsApp CTA-URL send failed: {$error}");
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

        $response = $this->postWithRateLimitRetry($tenant, "/{$tenant->whatsapp_phone_number_id}/messages", $payload);

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

    /**
     * Send a document (e.g. an invoice PDF) as a WhatsApp attachment — direct-Meta path only.
     * MoSMS's token API has no document/media-send endpoint today (see
     * docs/mosms-whatsapp-fixes-handoff.md), so this is never routed through MosmsService;
     * a MoSMS-only tenant has no whatsapp_phone_number_id/whatsapp_access_token and
     * validateCredentials() below rejects it the same way every other direct-Meta method does.
     *
     * Two-step Cloud API flow: upload the binary to Meta's media library to get a media id,
     * then reference that id in a `type: document` message — this keeps the PDF (which sits
     * behind our own auth) from ever needing a public unauthenticated URL for Meta to fetch.
     */
    public function sendDocument(Tenant $tenant, string $recipient, string $binary, string $filename, ?string $caption = null): array
    {
        $this->validateCredentials($tenant);

        $mediaId = $this->uploadMedia($tenant, $binary, $filename);

        $response = $this->postWithRateLimitRetry($tenant, "/{$tenant->whatsapp_phone_number_id}/messages", [
            'messaging_product' => 'whatsapp',
            'recipient_type' => 'individual',
            'to' => $this->formatPhone($recipient),
            'type' => 'document',
            'document' => array_filter([
                'id' => $mediaId,
                'filename' => $filename,
                'caption' => $caption,
            ], fn ($v) => $v !== null),
        ]);

        if (!$response->successful()) {
            $error = $response->json('error.message') ?? $response->body();
            Log::error('WhatsApp document send failed', [
                'tenant_id' => $tenant->id,
                'recipient' => $recipient,
                'filename' => $filename,
                'error' => $error,
            ]);
            throw new \RuntimeException("WhatsApp document send failed: {$error}");
        }

        return $response->json();
    }

    /**
     * Upload a binary to Meta's media library (POST /{phone-number-id}/media, multipart) and
     * return the resulting media id — valid for a single subsequent message send (Meta keeps
     * it for 30 days, but we never revisit it after the one send).
     */
    private function uploadMedia(Tenant $tenant, string $binary, string $filename): string
    {
        $response = Http::baseUrl("https://graph.facebook.com/{$this->apiVersion}")
            ->timeout($this->timeout)
            ->withToken($tenant->whatsapp_access_token)
            ->attach('file', $binary, $filename, ['Content-Type' => 'application/pdf'])
            ->post("/{$tenant->whatsapp_phone_number_id}/media", [
                'messaging_product' => 'whatsapp',
                'type' => 'application/pdf',
            ]);

        if (!$response->successful() || !$response->json('id')) {
            $error = $response->json('error.message') ?? $response->body();
            Log::error('WhatsApp media upload failed', [
                'tenant_id' => $tenant->id,
                'filename' => $filename,
                'error' => $error,
            ]);
            throw new \RuntimeException("WhatsApp media upload failed: {$error}");
        }

        return (string) $response->json('id');
    }

    /**
     * True when this tenant sends over its own Meta WhatsApp credentials rather than being
     * routed via MoSMS — the only path sendDocument() supports (see its docblock).
     */
    public function isDirectMeta(Tenant $tenant): bool
    {
        return !$this->useMosms($tenant);
    }

    /** POST to the Graph API, retrying with backoff on a 429 (rate limited) before giving up. */
    private function postWithRateLimitRetry(Tenant $tenant, string $path, array $payload): \Illuminate\Http\Client\Response
    {
        $client = Http::baseUrl("https://graph.facebook.com/{$this->apiVersion}")
            ->timeout($this->timeout)
            ->withToken($tenant->whatsapp_access_token);

        $attempt = 0;
        do {
            $response = $client->post($path, $payload);

            if ($response->successful() || $response->status() !== 429 || !isset(self::RATE_LIMIT_BACKOFF_SECONDS[$attempt])) {
                return $response;
            }

            Log::warning('WhatsApp Graph API rate limited, retrying', ['path' => $path, 'attempt' => $attempt + 1]);
            sleep(self::RATE_LIMIT_BACKOFF_SECONDS[$attempt]);
            $attempt++;
        } while (true);
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
