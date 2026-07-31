<?php

namespace App\Services;

use App\Models\MosmsAccount;
use App\Models\Tenant;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * HTTP client for MoSMS's token API (mosms.co.tz) — the same contract MoPOS
 * uses (Mosms_lib). WhatsApp messages are template-based on MoSMS's side:
 * free text is delivered through their approved 1-variable "custom_message"
 * wrapper template; named approved templates take an ordered variables list.
 * Auth is the tenant's own MoSMS Sanctum token (no server-to-server key);
 * every message debits the tenant's MoSMS whatsapp_balance (1 credit each).
 */
class MosmsService
{
    private string $base;
    private int $timeout;

    public function __construct()
    {
        $this->base = rtrim(config('services.mosms.base_url', 'https://mosms.co.tz/api'), '/');
        $this->timeout = (int) config('services.mosms.timeout', 30);
    }

    // ── Account linking ────────────────────────────────────────────────────

    /** Log in to an existing MoSMS account and store the token for this tenant. */
    public function link(Tenant $tenant, string $email, string $password): MosmsAccount
    {
        $res = $this->request('post', '/login', ['email' => $email, 'password' => $password]);
        return $this->storeAccount($tenant, $email, $res);
    }

    /** Register a brand-new MoSMS account for this tenant and store the token. */
    public function register(Tenant $tenant, array $data): MosmsAccount
    {
        $res = $this->request('post', '/register', [
            'org_name' => $data['org_name'],
            'name'     => $data['name'],
            'email'    => $data['email'],
            'phone'    => $data['phone'],
            'password' => $data['password'],
            'password_confirmation' => $data['password'],
        ]);

        return $this->storeAccount($tenant, $data['email'], $res);
    }

    public function accountFor(Tenant $tenant): ?MosmsAccount
    {
        return MosmsAccount::withoutGlobalScopes()->where('tenant_id', $tenant->id)->first();
    }

    public function isLinked(Tenant $tenant): bool
    {
        return (bool) $this->accountFor($tenant)?->isLinked();
    }

    // ── Reads ──────────────────────────────────────────────────────────────

    /** @return array{sms_balance:int|null, whatsapp_balance:int|null} */
    public function balance(Tenant $tenant): array
    {
        $res = $this->request('get', '/balance', null, $this->tokenFor($tenant));
        return [
            'sms_balance'      => $res['sms_balance'] ?? null,
            'whatsapp_balance' => $res['whatsapp_balance'] ?? null,
            'whatsapp_price'   => $res['whatsapp_price'] ?? null,
        ];
    }

    /** Approved WhatsApp templates visible to this tenant. */
    public function templates(Tenant $tenant): array
    {
        $res = $this->request('get', '/whatsapp/templates', null, $this->tokenFor($tenant));
        return $res['data'] ?? [];
    }

    /** Active SMS credit packages (name, quantity range, price per SMS). */
    public function packages(Tenant $tenant): array
    {
        $res = $this->request('get', '/sms-packages', null, $this->tokenFor($tenant));
        return $res['data'] ?? [];
    }

    /**
     * Start a Pesapal checkout for SMS credits.
     * @return array{payment_id:mixed, redirect_url:?string}
     */
    public function purchaseSms(Tenant $tenant, int $quantity, ?string $callbackUrl = null, string $channel = 'sms'): array
    {
        $res = $this->request('post', '/sms-purchases/pesapal', array_filter([
            'sms_quantity' => $quantity,
            'callback_url' => $callbackUrl,
            'channel'      => $channel,
        ]), $this->tokenFor($tenant));

        return [
            'payment_id'   => data_get($res, 'data.payment_id'),
            'redirect_url' => data_get($res, 'data.redirect_url'),
        ];
    }

    // ── Sends ──────────────────────────────────────────────────────────────

    /** Plain SMS through MoSMS (1 credit per 160-char segment). */
    public function sendSms(Tenant $tenant, string $to, string $text): array
    {
        return $this->request('post', '/sms/send', [
            'to'   => $to,
            'text' => $text,
        ], $this->tokenFor($tenant));
    }

    /** Free text — wrapped by MoSMS in their approved custom_message template. */
    public function sendText(Tenant $tenant, string $to, string $text): array
    {
        return $this->request('post', '/whatsapp/send', [
            'to'   => $to,
            'whatsapp_template_id' => $this->customTemplateId($tenant),
            'text' => $text,
        ], $this->tokenFor($tenant));
    }

    /** Named approved template with ordered variables (+ optional dynamic URL-button suffix). */
    public function sendTemplate(Tenant $tenant, string $to, string $template, array $variables = [], string $language = 'sw', ?string $buttonUrlParam = null): array
    {
        return $this->request('post', '/whatsapp/send', array_filter([
            'to'        => $to,
            'template'  => $template,
            'variables' => array_values(array_map('strval', $variables)),
            'language'  => $language,
            'button_url_param' => $buttonUrlParam,
        ], fn ($v) => $v !== null), $this->tokenFor($tenant));
    }

    // ── Internals ──────────────────────────────────────────────────────────

    private function storeAccount(Tenant $tenant, string $email, array $res): MosmsAccount
    {
        $account = MosmsAccount::withoutGlobalScopes()->firstOrNew(['tenant_id' => $tenant->id]);
        $account->fill([
            'tenant_id'      => $tenant->id,
            'email'          => $email,
            'token'          => $res['token'] ?? null,
            'mosms_tenant_id' => data_get($res, 'user.tenant.id'),
        ])->save();

        // Cache the custom_message wrapper id so free-text sends work.
        try {
            $account->update(['custom_template_id' => $this->findCustomTemplateId($account->token)]);
        } catch (\Throwable $e) {
            Log::warning('MoSMS: could not cache custom_message template id', ['error' => $e->getMessage()]);
        }

        return $account->refresh();
    }

    private function findCustomTemplateId(?string $token): ?int
    {
        if (!$token) {
            return null;
        }
        $res = $this->request('get', '/whatsapp/templates', null, $token);
        foreach ($res['data'] ?? [] as $t) {
            if (($t['name'] ?? '') === 'custom_message' && ($t['status'] ?? '') === 'approved') {
                return (int) $t['id'];
            }
        }
        return null;
    }

    private function customTemplateId(Tenant $tenant): int
    {
        $account = $this->accountFor($tenant);
        if (!$account?->custom_template_id) {
            // Try once to (re)discover it — it may have been approved since linking.
            $id = $this->findCustomTemplateId($account?->token);
            if ($id && $account) {
                $account->update(['custom_template_id' => $id]);
                return $id;
            }
            throw new \RuntimeException('MoSMS has no approved "custom_message" WhatsApp template for this account — free-text sending is unavailable.');
        }
        return (int) $account->custom_template_id;
    }

    private function tokenFor(Tenant $tenant): string
    {
        $token = $this->accountFor($tenant)?->token;
        if (!$token) {
            throw new \RuntimeException('This tenant has no linked MoSMS account.');
        }
        return $token;
    }

    /** @throws \RuntimeException on any non-2xx (message from MoSMS surfaced) */
    private function request(string $method, string $path, ?array $body, ?string $token = null): array
    {
        $client = Http::baseUrl($this->base)->acceptJson()->timeout($this->timeout);
        if ($token) {
            $client = $client->withToken($token);
        }

        $response = $method === 'get' ? $client->get($path, $body ?? []) : $client->post($path, $body ?? []);

        if (!$response->successful()) {
            $msg = $response->json('message') ?? $response->body();
            Log::error('MoSMS request failed', ['path' => $path, 'status' => $response->status(), 'message' => $msg]);
            throw new \RuntimeException("MoSMS: {$msg}");
        }

        return $response->json() ?? [];
    }
}
