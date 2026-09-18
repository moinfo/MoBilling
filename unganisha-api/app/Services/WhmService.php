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

    /**
     * WHM's "cpanel" passthrough — the only way to reach a cPanel-level
     * (UAPI/API2) function for one account, e.g. its email accounts. The
     * response shape is entirely different from every other call here
     * (`result.status`/`result.data`/`result.errors`, no top-level
     * `metadata.result`), so this can't share call()'s success check.
     */
    private function cpanelApi(string $user, string $module, string $func, array $params = [], array $sensitiveKeys = []): array
    {
        $request = Http::withHeaders([
            'Authorization' => "whm {$this->server->username}:{$this->server->api_token}",
        ])->timeout(30)->connectTimeout(15);

        if (!$this->server->verify_ssl) {
            $request = $request->withoutVerifying();
        }

        $url = "https://{$this->server->hostname}:{$this->server->port}/json-api/cpanel";
        $query = $params + [
            'api.version' => 1,
            'cpanel_jsonapi_user' => $user,
            'cpanel_jsonapi_apiversion' => 3,
            'cpanel_jsonapi_module' => $module,
            'cpanel_jsonapi_func' => $func,
        ];
        $logParams = ['user' => $user] + collect($params)->except($sensitiveKeys)->all();

        try {
            $response = $request->get($url, $query);
            $json = $response->json() ?? [];

            $ok = $response->ok() && (int) data_get($json, 'result.status', 0) === 1;
            $reason = $ok ? 'OK' : (implode('; ', (array) data_get($json, 'result.errors', [])) ?: 'HTTP ' . $response->status());

            $this->log("cpanel:{$module}:{$func}", $logParams, $ok ? (array) data_get($json, 'result.data', []) : $json, $ok, $ok ? null : $reason);

            if (!$ok) {
                throw new WhmApiException("{$module}::{$func}", $reason);
            }

            return (array) data_get($json, 'result.data', []);
        } catch (WhmApiException $e) {
            throw $e;
        } catch (\Throwable $e) {
            $this->log("cpanel:{$module}:{$func}", $logParams, null, false, $e->getMessage());
            throw new WhmApiException("{$module}::{$func}", $e->getMessage());
        }
    }

    /**
     * One account's email addresses with disk usage — "Main Account" is the
     * login itself, not a real mailbox. list_pops_with_disk's usage/quota
     * fields (`_diskused`, `_diskquota`) are bytes; `_diskquota` is `0` (int)
     * when unlimited, a numeric string otherwise — verified live.
     */
    public function emailAccounts(string $user): array
    {
        $rows = $this->cpanelApi($user, 'Email', 'list_pops_with_disk');
        return array_values(array_filter($rows, fn ($r) => ($r['login'] ?? '') !== 'Main Account'));
    }

    /**
     * $cpanelUser is the cPanel *account* owning the mailbox (same one
     * emailAccounts() was called with) — not derivable from $email alone,
     * since an addon domain's mailboxes don't share the account username.
     */

    /** Sets one mailbox's password — cPanel enforces its own strength check. */
    public function changeEmailPassword(string $cpanelUser, string $email, string $password): array
    {
        return $this->cpanelApi($cpanelUser, 'Email', 'passwd_pop', ['email' => $email, 'password' => $password], sensitiveKeys: ['password']);
    }

    public function suspendEmailLogin(string $cpanelUser, string $email): array
    {
        return $this->cpanelApi($cpanelUser, 'Email', 'suspend_login', ['email' => $email]);
    }

    public function unsuspendEmailLogin(string $cpanelUser, string $email): array
    {
        return $this->cpanelApi($cpanelUser, 'Email', 'unsuspend_login', ['email' => $email]);
    }

    /** Deletes a mailbox permanently — cPanel takes its mail store with it. */
    public function deleteEmailAccount(string $cpanelUser, string $email, string $domain): array
    {
        return $this->cpanelApi($cpanelUser, 'Email', 'delete_pop', ['email' => $email, 'domain' => $domain]);
    }

    /** One account's MySQL databases, each with its disk usage and linked users. */
    public function mysqlDatabases(string $user): array
    {
        return $this->cpanelApi($user, 'Mysql', 'list_databases');
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

    /**
     * Server-level vitals: hostname, WHM version, and 1/5/15-minute load
     * average. Three separate WHM calls (no combined endpoint exists) —
     * `listips` would round this out but the API token here gets
     * "Permission denied" on it (a reseller-level privilege gap, not a bug),
     * so it's deliberately left out rather than shown broken.
     */
    public function serverHealth(): array
    {
        return [
            'hostname' => data_get($this->call('gethostname'), 'data.hostname'),
            'whm_version' => data_get($this->call('version'), 'data.version'),
            'load_avg' => (function () {
                $d = data_get($this->call('systemloadavg'), 'data', []);
                return [
                    'one' => isset($d['one']) ? (float) $d['one'] : null,
                    'five' => isset($d['five']) ? (float) $d['five'] : null,
                    'fifteen' => isset($d['fifteen']) ? (float) $d['fifteen'] : null,
                ];
            })(),
        ];
    }

    /** @return string[] package names */
    public function listPackages(): array
    {
        $res = $this->call('listpkgs');
        return collect(data_get($res, 'data.pkg', []))->pluck('name')->all();
    }

    /**
     * Same WHM call as listPackages(), but keeps the resource limits instead
     * of discarding them — lets the product form auto-fill a catalog
     * description from the package's real specs instead of staff re-typing
     * numbers that live in WHM. WHM reports "unlimited" as the literal
     * string "unlimited" (or is sometimes just absent) — both become null.
     *
     * @return array<int, array{name: string, quota_mb: ?int, bandwidth_mb: ?int, databases: ?int, email_accounts: ?int, subdomains: ?int, ftp_accounts: ?int, addon_domains: ?int, parked_domains: ?int}>
     */
    public function listPackagesDetailed(): array
    {
        $res = $this->call('listpkgs');
        $limit = fn ($v) => (!isset($v) || strtolower((string) $v) === 'unlimited') ? null : (int) $v;

        return collect(data_get($res, 'data.pkg', []))->map(fn ($p) => [
            'name' => $p['name'] ?? '',
            'quota_mb' => $limit($p['QUOTA'] ?? null),
            'bandwidth_mb' => $limit($p['BWLIMIT'] ?? null),
            'databases' => $limit($p['MAXSQL'] ?? null),
            'email_accounts' => $limit($p['MAXPOP'] ?? null),
            'subdomains' => $limit($p['MAXSUB'] ?? null),
            'ftp_accounts' => $limit($p['MAXFTP'] ?? null),
            'addon_domains' => $limit($p['MAXADDON'] ?? null),
            'parked_domains' => $limit($p['MAXPARK'] ?? null),
        ])->values()->all();
    }

    /**
     * A domain's DNS zone, one row per record — WHM returns every string
     * field base64-encoded (`dname_b64`, `data_b64[]`), decoded here so
     * callers never touch raw base64. Comment/control lines (record_type
     * absent) are dropped; only real records are returned.
     *
     * @return array<int, array{type: string, name: string, ttl: int, data: string[]}>
     */
    public function dnsZone(string $domain): array
    {
        $res = $this->call('parse_dns_zone', ['zone' => $domain]);
        $lines = (array) data_get($res, 'data.payload', []);

        return collect($lines)
            ->filter(fn ($l) => ($l['type'] ?? null) === 'record')
            ->map(fn ($l) => [
                'type' => $l['record_type'] ?? '',
                'name' => isset($l['dname_raw']) ? $l['dname_raw'] : (isset($l['dname_b64']) ? base64_decode($l['dname_b64']) : ''),
                'ttl' => (int) ($l['ttl'] ?? 0),
                'data' => collect((array) ($l['data_b64'] ?? []))->map(fn ($d) => base64_decode($d))->all(),
            ])
            ->values()
            ->all();
    }

    public function accountSummary(string $user): array
    {
        $res = $this->call('accountsummary', ['user' => $user]);
        return (array) (data_get($res, 'data.acct.0') ?? []);
    }

    /** Every cPanel account on this server, per WHM — the server's own truth. */
    public function listAccounts(): array
    {
        $res = $this->call('listaccts');
        return (array) data_get($res, 'data.acct', []);
    }

    /**
     * Every domain on this server — main, addon, parked, and sub — each
     * tagged `domain_type` and (for sub/addon) `parent_domain`. No params
     * needed; this is server-wide, unlike accountSummary/listAccounts.
     */
    public function listDomains(): array
    {
        $res = $this->call('get_domain_info');
        return (array) data_get($res, 'data.domains', []);
    }

    /**
     * This month's bandwidth usage for every account, in one call — omitting
     * `user` returns the whole server, not just the caller's own reseller
     * accounts, unlike its name might suggest. accountsummary/listaccts
     * never carry usage — this is the only call that actually does.
     */
    public function bandwidthUsage(): array
    {
        $res = $this->call('showbw');
        return (array) data_get($res, 'data.acct', []);
    }

    // ── Mutations ──────────────────────────────────────────────────────────────

    /**
     * Shared param shape for addpkg/editpkg. Unlike setBandwidthLimit()'s
     * `0 = unlimited`, `bwlimit` here rejects both `0` and `"unlimited"`
     * outright (confirmed live — WHM's real "unlimited" for it is a fixed
     * huge number it applies itself, 1048576 MB, when the param is left out
     * entirely). So null in $limits OMITS that param rather than sending a
     * sentinel: on create that means "let WHM default it"; on edit it means
     * "leave it exactly as it is" — which is why the caller (the
     * controller) always sends every field's *current* value on an edit
     * rather than only the changed one.
     *
     * @param array{quota_mb?:?int, bandwidth_mb?:?int, databases?:?int, email_accounts?:?int, subdomains?:?int, ftp_accounts?:?int, addon_domains?:?int, parked_domains?:?int} $limits
     */
    private function packageParams(array $limits): array
    {
        return array_filter([
            'quota' => $limits['quota_mb'] ?? null,
            'bwlimit' => $limits['bandwidth_mb'] ?? null,
            'maxsql' => $limits['databases'] ?? null,
            'maxpop' => $limits['email_accounts'] ?? null,
            'maxsub' => $limits['subdomains'] ?? null,
            'maxftp' => $limits['ftp_accounts'] ?? null,
            'maxaddon' => $limits['addon_domains'] ?? null,
            'maxpark' => $limits['parked_domains'] ?? null,
        ], fn ($v) => $v !== null);
    }

    /**
     * Creates a new WHM package. $limits: see packageParams().
     *
     * Confirmed live: WHM silently prefixes the name with this reseller's
     * own username + "_" (every existing package in this system already
     * carries that same "moinfote_" prefix) — the name you pass is NOT the
     * name it ends up with. Callers should use {@see prefixedPackageName()}
     * to know what to display/store afterward.
     */
    public function createPackage(string $name, array $limits): array
    {
        return $this->call('addpkg', ['name' => $name] + $this->packageParams($limits));
    }

    /** The name WHM will actually give a package created with createPackage($name, ...). */
    public function prefixedPackageName(string $name): string
    {
        return str_starts_with($name, "{$this->server->username}_") ? $name : "{$this->server->username}_{$name}";
    }

    /** Edits an existing WHM package's limits — does not rename it. */
    public function updatePackage(string $name, array $limits): array
    {
        return $this->call('editpkg', ['pkgname' => $name] + $this->packageParams($limits));
    }

    /** Deletes a WHM package — WHM itself refuses if any account still uses it. */
    public function deletePackage(string $name): array
    {
        return $this->call('killpkg', ['pkgname' => $name]);
    }

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

    /** Changes the cPanel account's own contact email — WHM's "modifyacct". */
    public function changeContactEmail(string $user, string $email): array
    {
        return $this->call('modifyacct', ['user' => $user, 'contactemail' => $email]);
    }

    /**
     * Per-account bandwidth limit override, in megabytes — WHM's own
     * convention for "unlimited" here is 0, same as a disk quota of 0.
     * This is exactly what WHM's own suspend reason for a bandwidth-based
     * auto-suspend tells the admin to do ("Unsuspend by increasing
     * bandwidth limit") — raising the limit alone doesn't lift the
     * suspension, so callers should follow up with unsuspend().
     */
    public function setBandwidthLimit(string $user, ?int $limitMb = null): array
    {
        return $this->call('limitbw', ['user' => $user, 'bwlimit' => $limitMb ?? 0]);
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
