<?php

namespace App\Services;

use App\Exceptions\WhmApiException;
use App\Models\ProvisioningLog;
use App\Models\Server;
use Illuminate\Support\Facades\Http;

/**
 * WHM API 1 client (docs/WHM_CPANEL_INTEGRATION.md §5).
 *
 * All calls are HTTPS to https://{host}:{port}/json-api/{fn} with a
 * "whm user:token" Authorization header. Success = metadata.result == 1.
 * Every call is audited in provisioning_logs with credentials stripped.
 */
class WhmService
{
    public function __construct(private Server $server, private ?string $hostingAccountId = null) {}

    public function forAccount(?string $hostingAccountId): self
    {
        $this->hostingAccountId = $hostingAccountId;
        return $this;
    }

    private function call(string $fn, array $params = [], array $sensitiveKeys = []): array
    {
        $request = Http::withHeaders([
            'Authorization' => "whm {$this->server->username}:{$this->server->api_token}",
        ])->timeout(45)->connectTimeout(15);

        if (!$this->server->verify_ssl) {
            $request = $request->withoutVerifying();
        }

        $url = "https://{$this->server->hostname}:{$this->server->port}/json-api/{$fn}";
        $logParams = collect($params)->except($sensitiveKeys)->all();

        try {
            $response = $request->get($url, $params + ['api.version' => 1]);
            $json = $response->json() ?? [];

            $ok = $response->ok() && (int) data_get($json, 'metadata.result', 0) === 1;
            $reason = data_get($json, 'metadata.reason', $ok ? 'OK' : ('HTTP ' . $response->status()));

            $this->log($fn, $logParams, $ok ? (array) data_get($json, 'data', []) : $json, $ok, $ok ? null : $reason);

            if (!$ok) {
                throw new WhmApiException($fn, $reason);
            }

            return $json;
        } catch (WhmApiException $e) {
            throw $e;
        } catch (\Throwable $e) {
            $this->log($fn, $logParams, null, false, $e->getMessage());
            throw new WhmApiException($fn, $e->getMessage());
        }
    }

    private function log(string $action, array $request, ?array $response, bool $ok, ?string $error): void
    {
        try {
            ProvisioningLog::create([
                'tenant_id'          => $this->server->tenant_id,
                'hosting_account_id' => $this->hostingAccountId,
                'server_id'          => $this->server->id,
                'action'             => $action,
                'request'            => $request ?: null,
                // keep response payloads bounded
                'response'           => $response ? json_decode(mb_substr(json_encode($response), 0, 8000), true) : null,
                'status'             => $ok ? 'success' : 'failed',
                'error'              => $error,
            ]);
        } catch (\Throwable) {
            // auditing must never break provisioning
        }
    }

    // ── Read-only ──────────────────────────────────────────────────────────────

    /** @return string[] package names */
    public function listPackages(): array
    {
        $res = $this->call('listpkgs');
        return collect(data_get($res, 'data.pkg', []))->pluck('name')->all();
    }

    public function accountSummary(string $user): array
    {
        $res = $this->call('accountsummary', ['user' => $user]);
        return (array) (data_get($res, 'data.acct.0') ?? []);
    }

    // ── Mutations ──────────────────────────────────────────────────────────────

    public function createAccount(string $username, string $domain, string $password, string $plan, ?string $contactEmail = null): array
    {
        return $this->call('createacct', array_filter([
            'username'     => $username,
            'domain'       => $domain,
            'password'     => $password,
            'plan'         => $plan,
            'contactemail' => $contactEmail,
        ]), sensitiveKeys: ['password']);
    }

    public function suspend(string $user, string $reason = ''): array
    {
        return $this->call('suspendacct', array_filter(['user' => $user, 'reason' => $reason]));
    }

    public function unsuspend(string $user): array
    {
        return $this->call('unsuspendacct', ['user' => $user]);
    }

    public function terminate(string $user): array
    {
        return $this->call('removeacct', ['user' => $user]);
    }

    public function changePackage(string $user, string $package): array
    {
        return $this->call('changepackage', ['user' => $user, 'pkg' => $package]);
    }

    public function resetPassword(string $user, string $password): array
    {
        return $this->call('passwd', ['user' => $user, 'password' => $password], sensitiveKeys: ['password']);
    }

    /**
     * One-time SSO login URL. service: cpaneld (cPanel) or webmaild (Webmail).
     * $goto deep-links to a specific cPanel tool after login.
     */
    public function ssoUrl(string $user, string $service = 'cpaneld', ?string $goto = null): string
    {
        $res = $this->call('create_user_session', ['user' => $user, 'service' => $service]);
        $url = data_get($res, 'data.url');
        if (!$url) {
            throw new WhmApiException('create_user_session', 'No session URL returned');
        }
        if ($goto) {
            $url .= (str_contains($url, '?') ? '&' : '?') . 'goto_uri=' . urlencode($goto);
        }
        return $url;
    }
}
