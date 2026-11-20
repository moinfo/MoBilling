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
     * Creates a mailbox (Email::add_pop, verified live with a disposable
     * test mailbox — created, confirmed in emailAccounts(), deleted).
     * $quotaMb 0 = unlimited, matching every other quota field here.
     */
    public function addEmailAccount(string $cpanelUser, string $localPart, string $domain, string $password, int $quotaMb): array
    {
        return $this->cpanelApi($cpanelUser, 'Email', 'add_pop', [
            'email' => $localPart, 'domain' => $domain, 'password' => $password, 'quota' => $quotaMb,
        ], sensitiveKeys: ['password']);
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
     * Creates a new DNS-only zone (WHM API 1 `adddns` — confirmed against
     * the official spec, api.docs.cpanel.net/specifications/whm.openapi/
     * dns-zones/dns-adddns.md: `GET /adddns`, params `domain`/`ip`
     * required, `ipv6`/`template`/`trueowner` optional, response is
     * metadata-only exactly like every other call() here, no extra
     * `data.*` payload). WHM's standard template auto-generates the new
     * zone's own MX, PTR and A record(s) for the bare domain from
     * $domain/$ip alone — nothing else needs seeding right after this
     * succeeds. $trueowner left null means WHM attributes the zone to the
     * currently-authenticated (reseller) user rather than a cPanel account,
     * which is exactly right for a domain with no hosting account of its
     * own here.
     *
     * A zone created this way is a completely ordinary WHM DNS zone —
     * dnsZone()/addDnsRecord() below (parse_dns_zone/addzonerecord) already
     * take just a bare $domain name with no cPanel-account context, so they
     * work on it identically to a hosting account's zone; WHM's zone
     * storage doesn't distinguish "DNS-only" from "came bundled with a
     * cPanel account" at all.
     *
     * Deliberately no companion deletedns()/killdns — same add-only policy
     * as addDnsRecord() below, for the same reason (see its doc comment).
     * This method only ever creates a new zone; it never touches an
     * existing one.
     */
    public function createDnsZone(string $domain, string $ip, ?string $trueowner = null): array
    {
        return $this->call('adddns', array_filter([
            'domain'    => $domain,
            'ip'        => $ip,
            'trueowner' => $trueowner,
        ]));
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
     * For editing/removing an existing record, see editDnsRecord()/
     * removeDnsRecord() below — NOT a naive line number from this file's
     * own dnsZone()/parse_dns_zone: those line numbers do NOT match what
     * editzonerecord/removezonerecord themselves use for the same zone at
     * the same moment — confirmed live, twice, the hard way, in an earlier
     * version of this feature (a real customer's `_acme-challenge` and
     * `_cpanel-dcv-test-record` TXT records were each overwritten/deleted
     * by mistake this way, then restored). editDnsRecord()/
     * removeDnsRecord() instead re-derive the true line via a live
     * getzonerecord scan immediately before mutating — re-verified live
     * against a disposable test zone on 2026-11-21 (add/edit/remove,
     * duplicate-record disambiguation, and a deliberately-stale identity
     * that correctly refused) before being exposed in any UI.
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

    /**
     * Edits one existing DNS zone record. $old identifies which record to
     * target — {type, name, data[]} exactly as dnsZone() returned it when
     * the caller last read the zone — and is re-verified against a LIVE
     * getzonerecord scan taken this call, not the caller's (possibly
     * stale) copy, immediately before editzonerecord fires. This is the
     * only targeting method confirmed reliable live, on a disposable test
     * zone (several add/edit/remove cycles, 2026-11-21): parse_dns_zone's
     * line numbers never correspond to what editzonerecord/removezonerecord
     * expect — see addDnsRecord()'s doc comment for the two real-customer
     * incidents that cost. If $old no longer matches anything live (zone
     * changed since the caller last read it, or the identity given is
     * wrong), this throws rather than guess — it will never edit the
     * wrong line.
     *
     * @param array{type: string, name: string, data: string[]} $old
     */
    public function editDnsRecord(string $domain, array $old, string $type, string $name, int $ttl, array $data): array
    {
        $line = $this->findLiveLine($domain, $old);
        if ($line === null) {
            throw new WhmApiException('editzonerecord', "That record no longer matches what's live in the zone — please refresh and try again.");
        }

        return $this->call('editzonerecord', [
            'domain' => $domain,
            'line'   => $line,
            'name'   => $name,
            'class'  => 'IN',
            'ttl'    => $ttl,
            'type'   => $type,
        ] + $data);
    }

    /**
     * Removes one existing DNS zone record. Same live-rescan targeting as
     * editDnsRecord() above — see its doc comment. Note removezonerecord
     * takes `zone`, not `domain` (confirmed against the official WHM API
     * spec — editzonerecord's own parameters are undocumented there, which
     * is exactly why this whole targeting mechanism is tested live against
     * a disposable zone rather than assumed from the docs alone).
     *
     * @param array{type: string, name: string, data: string[]} $old
     */
    public function removeDnsRecord(string $domain, array $old): array
    {
        $line = $this->findLiveLine($domain, $old);
        if ($line === null) {
            throw new WhmApiException('removezonerecord', "That record no longer matches what's live in the zone — please refresh and try again.");
        }

        return $this->call('removezonerecord', ['zone' => $domain, 'line' => $line]);
    }

    /**
     * The one and only reliable way to find a record's true line number
     * for editzonerecord/removezonerecord: scan getzonerecord line by
     * line (never parse_dns_zone's line_index — confirmed live not to
     * match), matching on type + name + value. Bounded by double the
     * zone's own current record count (plus headroom for the SOA's extra
     * physical lines and the leading comment/$TTL lines) so this stays a
     * handful of calls even on a large zone.
     */
    private function findLiveLine(string $domain, array $old): ?int
    {
        $maxLine = count($this->dnsZone($domain)) * 2 + 20;
        $wantName = rtrim($old['name'], '.');
        $wantValue = implode('|', array_map(fn ($v) => rtrim((string) $v, '.'), $old['data']));

        for ($line = 1; $line <= $maxLine; $line++) {
            try {
                $res = $this->call('getzonerecord', ['domain' => $domain, 'line' => $line]);
            } catch (WhmApiException) {
                continue; // a gap (SOA's extra physical lines) or past the end — keep scanning up to $maxLine
            }

            $recs = (array) data_get($res, 'data.record', []);
            if (count($recs) !== 1) {
                continue; // SOA / malformed lines report back differently — never a candidate to edit/remove anyway
            }

            $rec = $recs[0];
            if (($rec['type'] ?? null) !== $old['type']) {
                continue;
            }
            if (strcasecmp(rtrim((string) ($rec['dname_raw'] ?? $rec['name'] ?? ''), '.'), $wantName) !== 0) {
                continue;
            }
            if (self::liveRecordValue($rec, $old['type']) === $wantValue) {
                return $line;
            }
        }

        return null;
    }

    /**
     * addzonerecord/editzonerecord's type-specific fields from a single
     * free-text value (+ MX priority) — the one place this mapping lives,
     * shared by every add/edit call site instead of repeating the same
     * match() in each controller.
     */
    public static function zoneRecordFields(string $type, ?string $value, ?int $priority = null): array
    {
        return match ($type) {
            'A', 'AAAA' => ['address' => $value],
            'CNAME'     => ['cname' => str_ends_with((string) $value, '.') ? $value : "{$value}."],
            'TXT'       => ['txtdata' => $value],
            'MX'        => ['preference' => $priority, 'exchange' => str_ends_with((string) $value, '.') ? $value : "{$value}."],
        };
    }

    /** getzonerecord's type-specific value field(s), normalised to the same "a|b" shape dnsZone()'s data[] uses. */
    private static function liveRecordValue(array $rec, string $type): string
    {
        return match ($type) {
            'A', 'AAAA' => rtrim((string) ($rec['address'] ?? ''), '.'),
            'CNAME'     => rtrim((string) ($rec['cname'] ?? ''), '.'),
            'TXT'       => (string) ($rec['txtdata'] ?? ''),
            'MX'        => rtrim((string) ($rec['preference'] ?? ''), '.') . '|' . rtrim((string) ($rec['exchange'] ?? ''), '.'),
            default     => '',
        };
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
