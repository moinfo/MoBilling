<?php

namespace App\Services\Registrar;

use App\Contracts\RegistrarDriver;
use App\Exceptions\RegistrarApiException;
use App\Models\DomainLog;
use App\Models\RegistrarAccount;
use Illuminate\Support\Facades\Http;

/**
 * .tz registrar driver: talks to the fred-client Django service (loopback,
 * DRF token auth), which speaks FRED-EPP to the TCRA registry.
 * Every call is audited in domain_logs (tokens never logged).
 */
class FredHttpDriver implements RegistrarDriver
{
    public function __construct(
        private RegistrarAccount $account,
        private ?string $domainId = null,
    ) {}

    public function forDomain(?string $domainId): self
    {
        $this->domainId = $domainId;
        return $this;
    }

    private function call(string $method, string $path, array $payload = []): array
    {
        // Bridge (MoBilling → fred-client) auth is the platform DRF token; a
        // tenant's EPP account has no bridge token of its own, so fall back to
        // the platform account's. (EPP creds go in the body, not this header.)
        $token = $this->account->credentials['service_token'] ?? null;
        if (!$token) {
            $token = RegistrarAccount::whereNull('tenant_id')->first()?->credentials['service_token'] ?? null;
        }
        if (!$token) {
            throw new RegistrarApiException($path, 'Registrar account has no service token configured');
        }

        $base = $this->account->endpoint_url
            ?: RegistrarAccount::whereNull('tenant_id')->first()?->endpoint_url;
        $url = rtrim((string) $base, '/') . $path;

        try {
            $response = Http::withHeaders(['Authorization' => "Token {$token}"])
                ->timeout(90)->connectTimeout(10)
                ->{$method}($url, $payload);

            $json = $response->json() ?? [];
            $ok = $response->successful();

            $this->log($path, $payload, $json, $ok, $ok ? null : ($json['detail'] ?? ('HTTP ' . $response->status())));

            if (!$ok) {
                throw new RegistrarApiException($path, $json['detail'] ?? $json['error'] ?? ('HTTP ' . $response->status()));
            }

            return $json;
        } catch (RegistrarApiException $e) {
            throw $e;
        } catch (\Throwable $e) {
            $this->log($path, $payload, null, false, $e->getMessage());
            throw new RegistrarApiException($path, $e->getMessage());
        }
    }

    private function log(string $action, array $request, ?array $response, bool $ok, ?string $error): void
    {
        // Never persist EPP secrets that ride in the request body (top-level
        // for credit, nested under 'creds' for register/renew/transfer).
        foreach (['certificate', 'private_key', 'password'] as $secret) {
            if (isset($request[$secret])) {
                $request[$secret] = '[redacted]';
            }
            if (isset($request['creds'][$secret])) {
                $request['creds'][$secret] = '[redacted]';
            }
        }

        try {
            DomainLog::create([
                'tenant_id' => $this->account->tenant_id,
                'domain_id' => $this->domainId,
                'action'    => $action,
                'request'   => $request ?: null,
                'response'  => $response ? json_decode(mb_substr(json_encode($response), 0, 8000), true) : null,
                'status'    => $ok ? 'success' : 'failed',
                'error'     => $error,
            ]);
        } catch (\Throwable) {
            // auditing must never break registrar operations
        }
    }

    // ── Read-only ──────────────────────────────────────────────────────────────

    public function check(string $domain): array
    {
        $res = $this->call('post', '/api/domains/check/', ['domain_names' => [$domain]]);
        $entry = $res['domains'][$domain] ?? null;

        // "The registry did not answer" is not the same as "the name is taken".
        // Defaulting a missing entry to unavailable made a broken or
        // misconfigured middleware look like a definitive answer, so every
        // visitor to the public search was told their domain was already gone.
        // Fail loudly instead — every caller already handles this exception.
        if ($entry === null || !array_key_exists('available', $entry)) {
            throw new RegistrarApiException('check', "No availability answer for {$domain}");
        }

        return ['available' => (bool) $entry['available'], 'reason' => $entry['reason'] ?? null];
    }

    public function info(string $domain): array
    {
        return $this->call('get', "/api/domains/{$domain}/info/");
    }

    public function credit(): array
    {
        // Tenant accounts carry their own EPP accreditation → connect under it;
        // the platform account uses the server-configured credentials (GET).
        if ($creds = $this->accountEppCreds()) {
            return $this->call('post', '/api/billing/credit/', $creds)['credits'] ?? [];
        }
        return $this->call('get', '/api/billing/credit/')['credits'] ?? [];
    }

    /** Attach the account's own EPP creds (nested) to a mutating payload, if any. */
    private function withCreds(array $payload): array
    {
        if ($creds = $this->accountEppCreds()) {
            $payload['creds'] = $creds;
        }
        return $payload;
    }

    /** Per-account EPP credentials to send to the bridge, or null for platform. */
    private function accountEppCreds(): ?array
    {
        $c = $this->account->credentials ?? [];
        if (empty($c['certificate']) || empty($c['private_key'])) {
            return null; // platform / server-configured
        }

        return [
            'registrar_id' => $this->account->registrar_id,
            'password'     => $c['password'] ?? '',
            'certificate'  => $c['certificate'],
            'private_key'  => $c['private_key'],
            'host'         => $c['host'] ?? null,
            'port'         => $c['port'] ?? null,
        ];
    }

    /** Read the oldest registry poll message WITHOUT dequeuing it (safe). */
    public function pollRequest(): array
    {
        return $this->call('get', '/api/billing/poll/');
    }

    /** Acknowledge/dequeue a registry poll message by id (irreversible). */
    public function pollAck(string $msgId): array
    {
        return $this->call('post', '/api/billing/poll/', ['msg_id' => $msgId]);
    }

    /** Live nameserver list for an NSset. */
    public function nssetInfo(string $nssetId): array
    {
        return $this->call('get', "/api/dns/nssets/{$nssetId}/");
    }

    /**
     * Change nameservers in an NSset (free EPP operation — no registry credit).
     * $add: [['name' => 'ns1.x.tz', 'addrs' => []], ...]; $remove: hostnames.
     */
    public function nssetUpdate(string $nssetId, array $add, array $remove): array
    {
        return $this->call('put', "/api/dns/nssets/{$nssetId}/update/", [
            'add_nameservers' => $add,
            'rem_nameservers' => $remove,
        ]);
    }

    // ── Paid / mutating (payment-gated jobs ONLY) ─────────────────────────────

    public function register(string $domain, int $years = 1, array $nameservers = []): array
    {
        return $this->call('post', '/api/domains/register/', $this->withCreds(array_filter([
            'domain_name'  => $domain,
            'period_years' => $years,
            'nameservers'  => $nameservers ?: null,
        ])));
    }

    public function renew(string $domain, int $years = 1): array
    {
        return $this->call('post', "/api/domains/{$domain}/renew/", $this->withCreds(['period_years' => $years]));
    }

    public function transferIn(string $domain, string $authInfo): array
    {
        return $this->call('post', '/api/domains/transfer/', $this->withCreds([
            'domain_name' => $domain,
            'auth_info'   => $authInfo,
        ]));
    }

    /**
     * EPP "SendAuthInfo": the registry emails the transfer/auth code directly
     * to the domain's registrant contact (the email on file at the registry —
     * not necessarily the same inbox as the MoBilling client record, though
     * in practice it usually matches for domains we registered on a client's
     * behalf). We never see the code itself; the registry delivers it.
     */
    public function sendAuthInfo(string $domain): array
    {
        return $this->call('post', "/api/domains/{$domain}/send-authinfo/");
    }

    /** Staff-only registry lookup — used to show WHERE a code was sent, never the code itself. */
    public function contactInfo(string $contactId): array
    {
        return $this->call('get', "/api/admin/registry/contact/{$contactId}/");
    }

    public function updateDomain(string $domain, array $changes): array
    {
        return $this->call('put', "/api/domains/{$domain}/update/", $changes);
    }

    /** Create a new NSset (free EPP operation). Returns the handle used. */
    public function nssetCreate(string $nssetId, array $nameservers, array $techContacts): array
    {
        return $this->call('post', '/api/dns/nssets/create/', [
            'nsset_id'      => $nssetId,
            'nameservers'   => $nameservers,
            'tech_contacts' => $techContacts,
        ]);
    }
}
