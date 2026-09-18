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
     * Same idea as cpanelApi(), but for cPanel API *2* — needed for the
     * Cron module, which isn't installed as a UAPI (v3) module on this
     * server ("Failed to load module Cpanel::API::Cron", verified live),
     * only the older API2 one. Response shape differs again:
     * `cpanelresult.event.result` for whether the *call* succeeded, but a
     * mutation (add_line/edit_line/remove_line) can report event.result=1
     * while still failing the actual operation via `data.0.status` (e.g.
     * remove_line on a linekey that's already gone returns "Cron job not
     * found in the crontab." this way) — verified live, so both are
     * checked. A `list`-type call's rows have no `status` key, so that
     * check is a no-op for them.
     */
    private function cpanelApi2(string $user, string $module, string $func, array $params = [], array $sensitiveKeys = []): array
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
            'cpanel_jsonapi_apiversion' => 2,
            'cpanel_jsonapi_module' => $module,
            'cpanel_jsonapi_func' => $func,
        ];
        $logParams = ['user' => $user] + collect($params)->except($sensitiveKeys)->all();

        try {
            $response = $request->get($url, $query);
            $json = $response->json() ?? [];
            $data = (array) data_get($json, 'cpanelresult.data', []);

            $eventOk = $response->ok() && (int) data_get($json, 'cpanelresult.event.result', 0) === 1;
            $itemStatus = data_get($data, '0.status');
            $ok = $eventOk && ($itemStatus === null || (int) $itemStatus === 1);
            $reason = $ok ? 'OK' : (data_get($data, '0.statusmsg') ?? data_get($json, 'cpanelresult.error') ?? ('HTTP ' . $response->status()));

            $this->log("cpanel2:{$module}:{$func}", $logParams, $ok ? $data : $json, $ok, $ok ? null : $reason);

            if (!$ok) {
                throw new WhmApiException("{$module}::{$func}", $reason);
            }

            return $data;
        } catch (WhmApiException $e) {
            throw $e;
        } catch (\Throwable $e) {
            $this->log("cpanel2:{$module}:{$func}", $logParams, null, false, $e->getMessage());
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

    /**
     * Dates (YYYY-MM-DD strings, newest first) of this account's existing
     * backups. Read-only — verified live via Backup::list_backups.
     */
    public function backupDates(string $user): array
    {
        return array_values($this->cpanelApi($user, 'Backup', 'list_backups'));
    }

    /**
     * Kicks off an on-demand full account backup to the account's own home
     * directory (Backup::fullbackup_to_homedir, verified live — returns the
     * backup process's PID). There is no WHM-level API1 function this
     * reseller token can use to toggle an account's inclusion in the
     * server's own scheduled backup run (backup_config_get/set and
     * modifyacct both come back "Permission denied") — this on-demand
     * trigger is the only backup lever available to the app.
     */
    public function triggerFullBackup(string $user): array
    {
        return $this->cpanelApi($user, 'Backup', 'fullbackup_to_homedir');
    }

    /**
     * The full-account backup tarballs fullbackup_to_homedir has left in
     * this account's home directory — `backup-<M.D.Y>_<H-i-s>_<user>.tar.gz`
     * at the home directory root, confirmed live via Fileman::list_files.
     * Scoped to that exact suffix so this only ever matches backups this
     * app (or the account's own WHM backup wizard) generated, never an
     * unrelated file the client happens to have in their home directory.
     * Sorted oldest first.
     */
    public function homeDirBackupFiles(string $user): array
    {
        $files = $this->cpanelApi($user, 'Fileman', 'list_files', ['dir' => '.', 'types' => 'file']);
        $suffix = "_{$user}.tar.gz";

        $rows = array_values(array_filter($files, function ($f) use ($suffix) {
            $name = $f['file'] ?? '';
            return str_starts_with($name, 'backup-') && str_ends_with($name, $suffix);
        }));

        usort($rows, fn ($a, $b) => ($a['mtime'] ?? 0) <=> ($b['mtime'] ?? 0));

        return array_map(fn ($f) => [
            'path'  => $f['fullpath'] ?? ($f['path'] . '/' . $f['file']),
            'mtime' => (int) ($f['mtime'] ?? 0),
            'bytes' => (int) ($f['size'] ?? 0),
        ], $rows);
    }

    /** Deletes one file from the account's filesystem (Fileman::delete_file — confirmed a permanent delete, no trash). */
    public function deleteFile(string $user, string $path): array
    {
        return $this->cpanelApi($user, 'Fileman', 'delete_file', ['path' => $path]);
    }

    /**
     * One account's cron jobs — Cron::listcron (API2), which unlike
     * fetchcron excludes the SHELL/MAILTO environment lines and gives a
     * clean row per command. Verified live.
     */
    public function cronJobs(string $user): array
    {
        return $this->cpanelApi2($user, 'Cron', 'listcron');
    }

    /**
     * @param array{minute:string,hour:string,day:string,month:string,weekday:string,command:string} $job
     * Returns ['linekey' => int] for the new line — verified live.
     */
    public function addCronJob(string $user, array $job): array
    {
        return ['linekey' => (int) data_get($this->cpanelApi2($user, 'Cron', 'add_line', $job), '0.linekey')];
    }

    /**
     * edit_line does not keep the same linekey — it reports a NEW one in
     * its response (verified live: editing a job returns a different
     * linekey than the one you passed in), so the caller must use this
     * returned value for any further action on the job, not the one it
     * started with.
     */
    public function updateCronJob(string $user, int $linekey, array $job): array
    {
        $result = $this->cpanelApi2($user, 'Cron', 'edit_line', ['linekey' => $linekey] + $job);
        return ['linekey' => (int) (data_get($result, '0.linekey') ?: $linekey)];
    }

    public function deleteCronJob(string $user, int $linekey): array
    {
        return $this->cpanelApi2($user, 'Cron', 'remove_line', ['linekey' => $linekey]);
    }

    /**
     * One account's FTP accounts (Ftp::list_ftp) — excludes the
     * `logaccess` row list_ftp always includes (an internal domlogs
     * entry, not a real user-manageable FTP login), verified live.
     */
    public function ftpAccounts(string $user): array
    {
        $rows = $this->cpanelApi($user, 'Ftp', 'list_ftp');
        return array_values(array_filter($rows, fn ($r) => ($r['type'] ?? null) !== 'logaccess'));
    }

    /**
     * Creates an FTP account. $homedir is relative to the cPanel account's
     * home directory (e.g. "public_html/uploads"). cPanel enforces its own
     * password-strength minimum (rejects anything scoring under ~95) —
     * verified live, surfaces as a normal WhmApiException with that
     * message. A sub-account's login comes back as "user@domain" (cPanel
     * appends the primary domain itself) — verified live, so the caller
     * must re-list rather than assume the plain $user is the final login.
     */
    public function addFtpAccount(string $user, string $ftpUser, string $password, string $homedir, int $quotaMb): array
    {
        return $this->cpanelApi($user, 'Ftp', 'add_ftp', [
            'user' => $ftpUser, 'pass' => $password, 'homedir' => $homedir, 'quota' => $quotaMb,
        ], sensitiveKeys: ['pass']);
    }

    /** $ftpUser is the full login as list_ftp reports it (e.g. "name@domain.tld" for a sub-account). */
    public function changeFtpPassword(string $user, string $ftpUser, string $password): array
    {
        return $this->cpanelApi($user, 'Ftp', 'passwd', ['user' => $ftpUser, 'pass' => $password], sensitiveKeys: ['pass']);
    }

    /** $destroy also deletes the account's files, not just its FTP login — off by default. */
    public function deleteFtpAccount(string $user, string $ftpUser, bool $destroy = false): array
    {
        return $this->cpanelApi($user, 'Ftp', 'delete_ftp', ['user' => $ftpUser, 'destroy' => $destroy ? 1 : 0]);
    }

    /**
     * One account's domains/subdomains with their current PHP version
     * (LangPHP::php_get_vhost_versions) — a UAPI-level, per-account call,
     * unlike the WHM-level php_get_vhost_versions/php_set_vhost_versions
     * (MultiPHP Manager), which this reseller token can't use at all
     * ("Permission denied", verified live). Same privilege-bypass pattern
     * as Backup/Fileman/Cron: acting AS the account sidesteps the
     * reseller ACL gap entirely.
     */
    public function phpVersions(string $user): array
    {
        return $this->cpanelApi($user, 'LangPHP', 'php_get_vhost_versions');
    }

    /** Every PHP version installed on the server (both EasyApache "ea-php*" and CloudLinux "alt-php*" stacks show up here). */
    public function installedPhpVersions(string $user): array
    {
        return (array) data_get($this->cpanelApi($user, 'LangPHP', 'php_get_installed_versions'), 'versions', []);
    }

    /** Sets one vhost's PHP version — verified live with a no-op (set to its own current version, confirmed unchanged). */
    public function setPhpVersion(string $user, string $vhost, string $version): array
    {
        return $this->cpanelApi($user, 'LangPHP', 'php_set_vhost_versions', ['version' => $version, 'vhost-0' => $vhost]);
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

    /**
     * Adds one DNS zone record. `$data` is type-specific — verified live
     * against a disposable test record for each shape (added, then
     * removed again):
     *   - A/AAAA:  ['address' => '1.2.3.4']
     *   - CNAME:   ['cname' => 'target.example.com.']
     *   - TXT:     ['txtdata' => '...']
     *   - MX:      ['preference' => 10, 'exchange' => 'mail.example.com.']
     * $name should be the FULL hostname (e.g. "sub.example.com."), not
     * just the label — addzonerecord takes it that way, not relative to
     * $domain the way a UI might otherwise assume.
     *
     * Deliberately no updateDnsRecord()/deleteDnsRecord() here: WHM's
     * editzonerecord/removezonerecord are line-number-based, and the line
     * numbers parse_dns_zone reports do NOT match what getzonerecord/
     * editzonerecord/removezonerecord themselves use for the same zone at
     * the same moment — confirmed live, twice, the hard way (a real
     * customer's `_acme-challenge` and `_cpanel-dcv-test-record` TXT
     * records were each overwritten/deleted by mistake this way, then
     * restored). The only line-number lookup that proved reliable was a
     * linear getzonerecord scan immediately before acting, re-verifying
     * the record's identity on that same line right before mutating it —
     * too slow and too fragile to expose as a normal UI action. Add-only,
     * until a safer identify-and-target mechanism is found.
     */
    public function addDnsRecord(string $domain, string $type, string $name, int $ttl, array $data): array
    {
        return $this->call('addzonerecord', [
            'domain' => $domain,
            'name' => $name,
            'type' => $type,
            'ttl' => $ttl,
            'class' => 'IN',
        ] + $data);
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
