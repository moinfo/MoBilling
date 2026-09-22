<?php

namespace App\Http\Controllers;

use App\Exceptions\WhmApiException;
use App\Jobs\Hosting\ChangeHostingPackage;
use App\Jobs\Hosting\ProvisionHostingAccount;
use App\Jobs\Hosting\ReactivateHostingAccount;
use App\Jobs\Hosting\SuspendHostingAccount;
use App\Jobs\Hosting\TerminateHostingAccount;
use App\Models\Client;
use App\Models\ClientSubscription;
use App\Models\Domain;
use App\Models\HostingAccount;
use App\Models\ProductService;
use App\Models\Server;
use App\Services\WhmService;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class HostingAccountController extends Controller
{
    /**
     * Every cPanel account that actually exists on the WHM server(s), cross
     * referenced against hosting_accounts so staff can see what's already
     * tracked in MoBilling and what was created directly on the server (or
     * missed during a WHMCS import) and still needs linking to a client.
     */
    public function discover(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $servers = Server::where('tenant_id', $tenantId)->where('is_active', true)
            ->when($request->filled('server_id'), fn ($q) => $q->where('id', $request->server_id))
            ->get();

        $known = HostingAccount::withoutGlobalScopes()
            ->where('tenant_id', $tenantId)
            ->with('subscription.client:id,name')
            ->get()
            ->keyBy(fn ($a) => $a->server_id . '|' . strtolower($a->cpanel_username));

        $rows = [];
        $errors = [];

        foreach ($servers as $server) {
            try {
                $remote = (new WhmService($server))->listAccounts();
            } catch (WhmApiException $e) {
                $errors[] = "{$server->name}: {$e->getMessage()}";
                continue;
            }

            foreach ($remote as $acct) {
                $username = (string) ($acct['user'] ?? '');
                if ($username === '') {
                    continue;
                }
                $local = $known->get($server->id . '|' . strtolower($username));

                $suspended = (bool) ($acct['suspended'] ?? false);
                $suspendReason = $acct['suspendreason'] ?? null;
                if ($suspendReason !== null && strcasecmp(trim($suspendReason), 'not suspended') === 0) {
                    $suspendReason = null;
                }

                $rows[] = [
                    'server_id'          => $server->id,
                    'server_name'        => $server->name,
                    'cpanel_username'    => $username,
                    'domain'             => $acct['domain'] ?? null,
                    'email'              => $acct['email'] ?? null,
                    'plan'               => $acct['plan'] ?? null,
                    'disk_used'          => $acct['diskused'] ?? null,
                    'disk_limit'         => $acct['disklimit'] ?? null,
                    'ip'                 => $acct['ip'] ?? null,
                    'setup_date'         => isset($acct['unix_startdate']) && $acct['unix_startdate']
                        ? \Carbon\Carbon::createFromTimestamp((int) $acct['unix_startdate'])->format('Y-m-d H:i')
                        : ($acct['startdate'] ?? null),
                    'partition'          => $acct['partition'] ?? null,
                    'theme'              => $acct['theme'] ?? null,
                    'owner'              => $acct['owner'] ?? null,
                    'suspended'          => $suspended,
                    // Only meaningful when actually suspended — WHM's own
                    // "not suspended" sentinel string is normalized to null
                    // above so the frontend can just check truthiness.
                    'suspend_reason'     => $suspended ? $suspendReason : null,
                    'hosting_account_id' => $local?->id,
                    'client_subscription_id' => $local?->client_subscription_id,
                    'client'             => $local?->subscription?->client
                        ? ['id' => $local->subscription->client->id, 'name' => $local->subscription->client->name]
                        : null,
                    'imported'           => (bool) $local,
                ];
            }
        }

        // Search across the merged list (username/domain/client name) —
        // simplest done after merging since it spans two data sources.
        if ($request->filled('search')) {
            $s = strtolower($request->search);
            $rows = array_values(array_filter($rows, fn ($r) =>
                str_contains(strtolower($r['cpanel_username']), $s)
                || str_contains(strtolower((string) $r['domain']), $s)
                || str_contains(strtolower((string) ($r['client']['name'] ?? '')), $s)));
        }
        if ($request->filled('imported')) {
            $want = $request->boolean('imported');
            $rows = array_values(array_filter($rows, fn ($r) => $r['imported'] === $want));
        }
        if ($request->filled('suspended')) {
            $want = $request->boolean('suspended');
            $rows = array_values(array_filter($rows, fn ($r) => $r['suspended'] === $want));
        }

        return response()->json(['data' => $rows, 'errors' => $errors]);
    }

    /**
     * Every subdomain AND addon domain across the tenant's WHM server(s) —
     * `get_domain_info` is server-wide and needs no per-account calls,
     * unlike discover()'s per-account listaccts loop. An addon domain is
     * still backed by a subdomain under the hood, which is why WHM tags
     * both the same way here (`domain_type`) rather than as unrelated
     * kinds of record.
     */
    public function subdomains(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $servers = Server::where('tenant_id', $tenantId)->where('is_active', true)
            ->when($request->filled('server_id'), fn ($q) => $q->where('id', $request->server_id))
            ->get();

        $known = HostingAccount::withoutGlobalScopes()
            ->where('tenant_id', $tenantId)
            ->with('subscription.client:id,name')
            ->get()
            ->keyBy(fn ($a) => $a->server_id . '|' . strtolower($a->cpanel_username));

        $rows = [];
        $errors = [];

        foreach ($servers as $server) {
            try {
                $domains = (new WhmService($server))->listDomains();
            } catch (WhmApiException $e) {
                $errors[] = "{$server->name}: {$e->getMessage()}";
                continue;
            }

            foreach ($domains as $d) {
                $type = $d['domain_type'] ?? null;
                if (!in_array($type, ['sub', 'addon'], true)) {
                    continue;
                }
                $username = (string) ($d['user'] ?? '');
                $local = $username !== '' ? $known->get($server->id . '|' . strtolower($username)) : null;

                $rows[] = [
                    'server_id'       => $server->id,
                    'server_name'     => $server->name,
                    'type'            => $type,
                    'subdomain'       => $d['domain'] ?? null,
                    'parent_domain'   => $d['parent_domain'] ?? null,
                    'cpanel_username' => $username,
                    'docroot'         => $d['docroot'] ?? null,
                    'ip'              => $d['ipv4'] ?? null,
                    'php_version'     => $d['php_version'] ?: null,
                    'client'          => $local?->subscription?->client
                        ? ['id' => $local->subscription->client->id, 'name' => $local->subscription->client->name]
                        : null,
                ];
            }
        }

        if ($request->filled('type')) {
            $rows = array_values(array_filter($rows, fn ($r) => $r['type'] === $request->type));
        }
        if ($request->filled('search')) {
            $s = strtolower($request->search);
            $rows = array_values(array_filter($rows, fn ($r) =>
                str_contains(strtolower((string) $r['subdomain']), $s)
                || str_contains(strtolower((string) $r['parent_domain']), $s)
                || str_contains(strtolower($r['cpanel_username']), $s)
                || str_contains(strtolower((string) ($r['client']['name'] ?? '')), $s)));
        }

        usort($rows, fn ($a, $b) => strcmp((string) $a['subdomain'], (string) $b['subdomain']));

        return response()->json(['data' => $rows, 'errors' => $errors]);
    }

    /**
     * This month's bandwidth usage for every cPanel account across the
     * tenant's WHM server(s), sorted worst-first — the proactive
     * counterpart to "Fix Bandwidth Suspension": see who's approaching
     * their limit before WHM's own cron suspends them for it.
     */
    public function bandwidthUsage(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $servers = Server::where('tenant_id', $tenantId)->where('is_active', true)
            ->when($request->filled('server_id'), fn ($q) => $q->where('id', $request->server_id))
            ->get();

        $known = HostingAccount::withoutGlobalScopes()
            ->where('tenant_id', $tenantId)
            ->with('subscription.client:id,name')
            ->get()
            ->keyBy(fn ($a) => $a->server_id . '|' . strtolower($a->cpanel_username));

        $rows = [];
        $errors = [];

        foreach ($servers as $server) {
            try {
                $accounts = (new WhmService($server))->bandwidthUsage();
            } catch (WhmApiException $e) {
                $errors[] = "{$server->name}: {$e->getMessage()}";
                continue;
            }

            foreach ($accounts as $a) {
                $username = (string) ($a['user'] ?? '');
                if ($username === '') {
                    continue;
                }
                $local = $known->get($server->id . '|' . strtolower($username));

                $usedBytes  = (int) ($a['totalbytes'] ?? 0);
                $limitBytes = (int) ($a['limit'] ?? 0); // 0 = unlimited, WHM's own convention
                $percent    = $limitBytes > 0 ? round(($usedBytes / $limitBytes) * 100, 1) : null;

                $rows[] = [
                    'server_id'          => $server->id,
                    'server_name'        => $server->name,
                    'cpanel_username'    => $username,
                    'domain'             => $a['maindomain'] ?? null,
                    'used_bytes'         => $usedBytes,
                    'limit_bytes'        => $limitBytes > 0 ? $limitBytes : null,
                    'percent_used'       => $percent,
                    'bandwidth_limited'  => (bool) ($a['bwlimited'] ?? false),
                    'client'             => $local?->subscription?->client
                        ? ['id' => $local->subscription->client->id, 'name' => $local->subscription->client->name]
                        : null,
                ];
            }
        }

        if ($request->filled('search')) {
            $s = strtolower($request->search);
            $rows = array_values(array_filter($rows, fn ($r) =>
                str_contains(strtolower($r['cpanel_username']), $s)
                || str_contains(strtolower((string) $r['domain']), $s)
                || str_contains(strtolower((string) ($r['client']['name'] ?? '')), $s)));
        }

        // Highest usage first; unlimited accounts (no percent) sort last.
        usort($rows, fn ($a, $b) => ($b['percent_used'] ?? -1) <=> ($a['percent_used'] ?? -1));

        return response()->json(['data' => $rows, 'errors' => $errors]);
    }

    /**
     * Disk usage for every cPanel account across the tenant's WHM server(s),
     * sorted worst-first — same idea as bandwidthUsage(), but disk_used/
     * disk_limit are already in listaccts (no extra WHM call needed).
     */
    public function diskUsage(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $servers = Server::where('tenant_id', $tenantId)->where('is_active', true)
            ->when($request->filled('server_id'), fn ($q) => $q->where('id', $request->server_id))
            ->get();

        $known = HostingAccount::withoutGlobalScopes()
            ->where('tenant_id', $tenantId)
            ->with('subscription.client:id,name')
            ->get()
            ->keyBy(fn ($a) => $a->server_id . '|' . strtolower($a->cpanel_username));

        // "563M" -> 563, "unlimited" (or missing) -> null.
        $toMb = function ($raw) {
            if (!is_string($raw) || !preg_match('/^(\d+(?:\.\d+)?)M$/i', trim($raw), $m)) {
                return null;
            }
            return (float) $m[1];
        };

        $rows = [];
        $errors = [];

        foreach ($servers as $server) {
            try {
                $accounts = (new WhmService($server))->listAccounts();
            } catch (WhmApiException $e) {
                $errors[] = "{$server->name}: {$e->getMessage()}";
                continue;
            }

            foreach ($accounts as $a) {
                $username = (string) ($a['user'] ?? '');
                if ($username === '') {
                    continue;
                }
                $local = $known->get($server->id . '|' . strtolower($username));

                $usedMb  = $toMb($a['diskused'] ?? null) ?? 0;
                $limitMb = $toMb($a['disklimit'] ?? null);
                $percent = $limitMb !== null && $limitMb > 0 ? round(($usedMb / $limitMb) * 100, 1) : null;

                $rows[] = [
                    'server_id'       => $server->id,
                    'server_name'     => $server->name,
                    'cpanel_username' => $username,
                    'domain'          => $a['domain'] ?? null,
                    'used_mb'         => $usedMb,
                    'limit_mb'        => $limitMb,
                    'percent_used'    => $percent,
                    'client'          => $local?->subscription?->client
                        ? ['id' => $local->subscription->client->id, 'name' => $local->subscription->client->name]
                        : null,
                ];
            }
        }

        if ($request->filled('search')) {
            $s = strtolower($request->search);
            $rows = array_values(array_filter($rows, fn ($r) =>
                str_contains(strtolower($r['cpanel_username']), $s)
                || str_contains(strtolower((string) $r['domain']), $s)
                || str_contains(strtolower((string) ($r['client']['name'] ?? '')), $s)));
        }

        usort($rows, fn ($a, $b) => ($b['percent_used'] ?? -1) <=> ($a['percent_used'] ?? -1));

        return response()->json(['data' => $rows, 'errors' => $errors]);
    }

    /**
     * Backup status for every cPanel account — listaccts carries two
     * distinct flags: `backup` (the setting is turned on) and `has_backup`
     * (a backup file actually exists). Verified live they genuinely
     * diverge — some accounts have the setting on with no backup on disk
     * yet, which is the exact risk this view exists to surface. Sorted
     * worst-first: no backup and no setting, then setting-on-but-missing,
     * then everyone else.
     */
    public function backupStatus(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $servers = Server::where('tenant_id', $tenantId)->where('is_active', true)
            ->when($request->filled('server_id'), fn ($q) => $q->where('id', $request->server_id))
            ->get();

        $known = HostingAccount::withoutGlobalScopes()
            ->where('tenant_id', $tenantId)
            ->with('subscription.client:id,name')
            ->get()
            ->keyBy(fn ($a) => $a->server_id . '|' . strtolower($a->cpanel_username));

        $rows = [];
        $errors = [];

        foreach ($servers as $server) {
            try {
                $accounts = (new WhmService($server))->listAccounts();
            } catch (WhmApiException $e) {
                $errors[] = "{$server->name}: {$e->getMessage()}";
                continue;
            }

            foreach ($accounts as $a) {
                $username = (string) ($a['user'] ?? '');
                if ($username === '') {
                    continue;
                }
                $local = $known->get($server->id . '|' . strtolower($username));

                $rows[] = [
                    'server_id'          => $server->id,
                    'server_name'        => $server->name,
                    'cpanel_username'    => $username,
                    'domain'             => $a['domain'] ?? null,
                    'backup_enabled'     => (bool) ($a['backup'] ?? false),
                    'backup_exists'      => (bool) ($a['has_backup'] ?? false),
                    'client'             => $local?->subscription?->client
                        ? ['id' => $local->subscription->client->id, 'name' => $local->subscription->client->name]
                        : null,
                ];
            }
        }

        if ($request->filled('search')) {
            $s = strtolower($request->search);
            $rows = array_values(array_filter($rows, fn ($r) =>
                str_contains(strtolower($r['cpanel_username']), $s)
                || str_contains(strtolower((string) $r['domain']), $s)
                || str_contains(strtolower((string) ($r['client']['name'] ?? '')), $s)));
        }

        // Worst first: neither enabled nor existing, then missing despite
        // being enabled, then the rest.
        $risk = fn ($r) => !$r['backup_enabled'] && !$r['backup_exists'] ? 0
            : ($r['backup_enabled'] && !$r['backup_exists'] ? 1 : 2);
        usort($rows, fn ($a, $b) => $risk($a) <=> $risk($b));

        return response()->json(['data' => $rows, 'errors' => $errors]);
    }

    /**
     * One account's email addresses — unlike every other report here, WHM
     * has no bulk call for this (email accounts are cPanel/UAPI-level, one
     * "cpanel" passthrough call per account), so this deliberately takes a
     * single account rather than looping the whole server.
     */
    public function emailAccounts(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'server_id'       => ['required', 'uuid', Rule::exists('servers', 'id')->where('tenant_id', $tenantId)],
            'cpanel_username' => 'required|string|max:64',
        ]);

        $server = Server::where('tenant_id', $tenantId)->findOrFail($data['server_id']);

        try {
            $pops = (new WhmService($server))->emailAccounts($data['cpanel_username']);
        } catch (WhmApiException $e) {
            return response()->json(['message' => 'Server rejected the request: ' . $e->getMessage()], 422);
        }

        // list_pops_with_disk's quota is 0 (int) when unlimited, a numeric
        // byte-count string otherwise — verified live.
        $rows = array_map(function ($p) {
            $quotaRaw = $p['_diskquota'] ?? 0;
            $quotaBytes = (int) $quotaRaw;
            return [
                'email'              => $p['email'] ?? null,
                'suspended_incoming' => (bool) ($p['suspended_incoming'] ?? false),
                'suspended_login'    => (bool) ($p['suspended_login'] ?? false),
                'used_bytes'         => (int) ($p['_diskused'] ?? 0),
                'quota_bytes'        => $quotaBytes > 0 ? $quotaBytes : null,
            ];
        }, $pops);

        return response()->json(['data' => $rows]);
    }

    /** Creates a mailbox. */
    public function storeEmailAccount(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'server_id'       => ['required', 'uuid', Rule::exists('servers', 'id')->where('tenant_id', $tenantId)],
            'cpanel_username' => 'required|string|max:64',
            'email'           => 'required|string|max:64|regex:/^[a-zA-Z0-9._+-]+$/',
            'domain'          => 'required|string|max:255',
            'password'        => 'required|string|min:8|max:255',
            'quota_mb'        => 'required|integer|min:0',
        ]);

        $server = Server::where('tenant_id', $tenantId)->findOrFail($data['server_id']);

        try {
            (new WhmService($server))->addEmailAccount($data['cpanel_username'], $data['email'], $data['domain'], $data['password'], $data['quota_mb']);
        } catch (WhmApiException $e) {
            return response()->json(['message' => 'Server rejected the request: ' . $e->getMessage()], 422);
        }

        return response()->json(['message' => 'Email account created.']);
    }

    /** Module command: set one mailbox's password. */
    public function changeEmailPassword(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'server_id'       => ['required', 'uuid', Rule::exists('servers', 'id')->where('tenant_id', $tenantId)],
            'cpanel_username' => 'required|string|max:64',
            'email'           => 'required|email|max:255',
            'password'        => 'required|string|min:8|max:255',
        ]);

        $server = Server::where('tenant_id', $tenantId)->findOrFail($data['server_id']);

        try {
            (new WhmService($server))->changeEmailPassword($data['cpanel_username'], $data['email'], $data['password']);
        } catch (WhmApiException $e) {
            return response()->json(['message' => 'Server rejected the change: ' . $e->getMessage()], 422);
        }

        return response()->json(['message' => 'Mailbox password changed.']);
    }

    /** Module command: suspend or unsuspend one mailbox's login (webmail/IMAP/POP). */
    public function toggleEmailSuspension(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'server_id'       => ['required', 'uuid', Rule::exists('servers', 'id')->where('tenant_id', $tenantId)],
            'cpanel_username' => 'required|string|max:64',
            'email'           => 'required|email|max:255',
            'suspend'         => 'required|boolean',
        ]);

        $server = Server::where('tenant_id', $tenantId)->findOrFail($data['server_id']);
        $whm = new WhmService($server);

        try {
            $data['suspend']
                ? $whm->suspendEmailLogin($data['cpanel_username'], $data['email'])
                : $whm->unsuspendEmailLogin($data['cpanel_username'], $data['email']);
        } catch (WhmApiException $e) {
            return response()->json(['message' => 'Server rejected the change: ' . $e->getMessage()], 422);
        }

        return response()->json(['message' => $data['suspend'] ? 'Mailbox login suspended.' : 'Mailbox login unsuspended.']);
    }

    /** Deletes one mailbox permanently — cPanel takes its mail store with it. */
    public function deleteEmailAccount(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'server_id'       => ['required', 'uuid', Rule::exists('servers', 'id')->where('tenant_id', $tenantId)],
            'cpanel_username' => 'required|string|max:64',
            'email'           => 'required|email|max:255',
            'domain'          => 'required|string|max:255',
        ]);

        $server = Server::where('tenant_id', $tenantId)->findOrFail($data['server_id']);

        try {
            (new WhmService($server))->deleteEmailAccount($data['cpanel_username'], $data['email'], $data['domain']);
        } catch (WhmApiException $e) {
            return response()->json(['message' => 'Server rejected the delete: ' . $e->getMessage()], 422);
        }

        return response()->json(['message' => 'Mailbox deleted.']);
    }

    /** One account's MySQL databases — same per-account shape as emailAccounts(). */
    public function mysqlDatabases(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'server_id'       => ['required', 'uuid', Rule::exists('servers', 'id')->where('tenant_id', $tenantId)],
            'cpanel_username' => 'required|string|max:64',
        ]);

        $server = Server::where('tenant_id', $tenantId)->findOrFail($data['server_id']);

        try {
            $dbs = (new WhmService($server))->mysqlDatabases($data['cpanel_username']);
        } catch (WhmApiException $e) {
            return response()->json(['message' => 'Server rejected the request: ' . $e->getMessage()], 422);
        }

        $rows = array_map(fn ($d) => [
            'database'   => $d['database'] ?? null,
            'users'      => (array) ($d['users'] ?? []),
            'disk_usage' => (int) ($d['disk_usage'] ?? 0),
        ], $dbs);

        return response()->json(['data' => $rows]);
    }

    /**
     * A domain's DNS zone — read-only for now (view only, per explicit
     * decision, before any edit capability ships). Takes the domain name
     * directly rather than cpanel_username: WHM's parse_dns_zone is keyed
     * by zone name, and a subdomain/addon domain has its own zone that
     * doesn't share the account's cpanel username.
     */
    public function dnsZone(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'server_id' => ['required', 'uuid', Rule::exists('servers', 'id')->where('tenant_id', $tenantId)],
            'domain'    => 'required|string|max:255',
        ]);

        $server = Server::where('tenant_id', $tenantId)->findOrFail($data['server_id']);

        try {
            $records = (new WhmService($server))->dnsZone($data['domain']);
        } catch (WhmApiException $e) {
            return response()->json(['message' => 'Server rejected the request: ' . $e->getMessage()], 422);
        }

        return response()->json(['data' => $records]);
    }

    /**
     * Adds one DNS zone record. Add-only, deliberately — see
     * WhmService::addDnsRecord()'s doc comment for why edit/delete aren't
     * exposed here (WHM's line-number-based edit/remove calls proved
     * unreliable during live verification: two real records were
     * accidentally overwritten/deleted before this was caught and reverted).
     */
    public function addDnsRecord(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'server_id' => ['required', 'uuid', Rule::exists('servers', 'id')->where('tenant_id', $tenantId)],
            'domain'    => 'required|string|max:255',
            'type'      => ['required', Rule::in(['A', 'AAAA', 'CNAME', 'TXT', 'MX'])],
            'name'      => 'required|string|max:255',
            'ttl'       => 'required|integer|min:60|max:2592000',
            'value'     => 'required_unless:type,MX|nullable|string|max:1024',
            'priority'  => 'required_if:type,MX|nullable|integer|min:0|max:65535',
        ]);

        $server = Server::where('tenant_id', $tenantId)->findOrFail($data['server_id']);
        $name = str_ends_with($data['name'], '.') ? $data['name'] : "{$data['name']}.";

        $fields = match ($data['type']) {
            'A', 'AAAA' => ['address' => $data['value']],
            'CNAME' => ['cname' => str_ends_with($data['value'], '.') ? $data['value'] : "{$data['value']}."],
            'TXT' => ['txtdata' => $data['value']],
            'MX' => ['preference' => $data['priority'], 'exchange' => str_ends_with($data['value'], '.') ? $data['value'] : "{$data['value']}."],
        };

        try {
            (new WhmService($server))->addDnsRecord($data['domain'], $data['type'], $name, $data['ttl'], $fields);
        } catch (WhmApiException $e) {
            return response()->json(['message' => 'Server rejected the record: ' . $e->getMessage()], 422);
        }

        return response()->json(['message' => 'DNS record added.']);
    }

    /** One account's cron jobs — WhmService::cronJobs() (cPanel API2's Cron::listcron). */
    public function cronJobs(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'server_id'       => ['required', 'uuid', Rule::exists('servers', 'id')->where('tenant_id', $tenantId)],
            'cpanel_username' => 'required|string|max:64',
        ]);

        $server = Server::where('tenant_id', $tenantId)->findOrFail($data['server_id']);

        try {
            $jobs = (new WhmService($server))->cronJobs($data['cpanel_username']);
        } catch (WhmApiException $e) {
            return response()->json(['message' => 'Server rejected the request: ' . $e->getMessage()], 422);
        }

        return response()->json(['data' => $jobs]);
    }

    private function cronJobRules(): array
    {
        return [
            'minute'  => 'required|string|max:100',
            'hour'    => 'required|string|max:100',
            'day'     => 'required|string|max:100',
            'month'   => 'required|string|max:100',
            'weekday' => 'required|string|max:100',
            'command' => 'required|string|max:2000',
        ];
    }

    public function storeCronJob(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'server_id'       => ['required', 'uuid', Rule::exists('servers', 'id')->where('tenant_id', $tenantId)],
            'cpanel_username' => 'required|string|max:64',
        ] + $this->cronJobRules());

        $server = Server::where('tenant_id', $tenantId)->findOrFail($data['server_id']);

        try {
            (new WhmService($server))->addCronJob($data['cpanel_username'], collect($data)->only(['minute', 'hour', 'day', 'month', 'weekday', 'command'])->all());
        } catch (WhmApiException $e) {
            return response()->json(['message' => 'Server rejected the cron job: ' . $e->getMessage()], 422);
        }

        return response()->json(['message' => 'Cron job added.']);
    }

    public function updateCronJob(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'server_id'       => ['required', 'uuid', Rule::exists('servers', 'id')->where('tenant_id', $tenantId)],
            'cpanel_username' => 'required|string|max:64',
            'linekey'         => 'required|integer',
        ] + $this->cronJobRules());

        $server = Server::where('tenant_id', $tenantId)->findOrFail($data['server_id']);

        try {
            (new WhmService($server))->updateCronJob($data['cpanel_username'], $data['linekey'], collect($data)->only(['minute', 'hour', 'day', 'month', 'weekday', 'command'])->all());
        } catch (WhmApiException $e) {
            return response()->json(['message' => 'Server rejected the change: ' . $e->getMessage()], 422);
        }

        return response()->json(['message' => 'Cron job updated.']);
    }

    public function destroyCronJob(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'server_id'       => ['required', 'uuid', Rule::exists('servers', 'id')->where('tenant_id', $tenantId)],
            'cpanel_username' => 'required|string|max:64',
            'linekey'         => 'required|integer',
        ]);

        $server = Server::where('tenant_id', $tenantId)->findOrFail($data['server_id']);

        try {
            (new WhmService($server))->deleteCronJob($data['cpanel_username'], $data['linekey']);
        } catch (WhmApiException $e) {
            return response()->json(['message' => 'Server rejected the delete: ' . $e->getMessage()], 422);
        }

        return response()->json(['message' => 'Cron job deleted.']);
    }

    /** One account's domains/subdomains with their current PHP version, plus what's installed on the server. */
    public function phpVersions(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'server_id'       => ['required', 'uuid', Rule::exists('servers', 'id')->where('tenant_id', $tenantId)],
            'cpanel_username' => 'required|string|max:64',
        ]);

        $server = Server::where('tenant_id', $tenantId)->findOrFail($data['server_id']);
        $whm = new WhmService($server);

        try {
            $vhosts = $whm->phpVersions($data['cpanel_username']);
            $installed = $whm->installedPhpVersions($data['cpanel_username']);
        } catch (WhmApiException $e) {
            return response()->json(['message' => 'Server rejected the request: ' . $e->getMessage()], 422);
        }

        $rows = array_map(fn ($v) => [
            'vhost'       => $v['vhost'] ?? null,
            'version'     => $v['version'] ?? null,
            'main_domain' => (bool) ($v['main_domain'] ?? false),
        ], $vhosts);

        return response()->json(['data' => $rows, 'installed' => $installed]);
    }

    public function updatePhpVersion(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'server_id'       => ['required', 'uuid', Rule::exists('servers', 'id')->where('tenant_id', $tenantId)],
            'cpanel_username' => 'required|string|max:64',
            'vhost'           => 'required|string|max:255',
            'version'         => 'required|string|max:32',
        ]);

        $server = Server::where('tenant_id', $tenantId)->findOrFail($data['server_id']);

        try {
            (new WhmService($server))->setPhpVersion($data['cpanel_username'], $data['vhost'], $data['version']);
        } catch (WhmApiException $e) {
            return response()->json(['message' => 'Server rejected the change: ' . $e->getMessage()], 422);
        }

        return response()->json(['message' => 'PHP version updated.']);
    }

    /** One account's FTP accounts — WhmService::ftpAccounts() (cPanel UAPI's Ftp::list_ftp). */
    public function ftpAccounts(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'server_id'       => ['required', 'uuid', Rule::exists('servers', 'id')->where('tenant_id', $tenantId)],
            'cpanel_username' => 'required|string|max:64',
        ]);

        $server = Server::where('tenant_id', $tenantId)->findOrFail($data['server_id']);

        try {
            $rows = (new WhmService($server))->ftpAccounts($data['cpanel_username']);
        } catch (WhmApiException $e) {
            return response()->json(['message' => 'Server rejected the request: ' . $e->getMessage()], 422);
        }

        return response()->json(['data' => $rows]);
    }

    public function storeFtpAccount(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'server_id'       => ['required', 'uuid', Rule::exists('servers', 'id')->where('tenant_id', $tenantId)],
            'cpanel_username' => 'required|string|max:64',
            'user'            => 'required|string|max:64|regex:/^[a-zA-Z0-9_.-]+$/',
            'password'        => 'required|string|min:8|max:255',
            'homedir'         => 'required|string|max:255',
            'quota_mb'        => 'required|integer|min:0',
        ]);

        $server = Server::where('tenant_id', $tenantId)->findOrFail($data['server_id']);

        try {
            (new WhmService($server))->addFtpAccount($data['cpanel_username'], $data['user'], $data['password'], $data['homedir'], $data['quota_mb']);
        } catch (WhmApiException $e) {
            return response()->json(['message' => 'Server rejected the request: ' . $e->getMessage()], 422);
        }

        return response()->json(['message' => 'FTP account created.']);
    }

    public function updateFtpAccountPassword(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'server_id'       => ['required', 'uuid', Rule::exists('servers', 'id')->where('tenant_id', $tenantId)],
            'cpanel_username' => 'required|string|max:64',
            'user'            => 'required|string|max:255',
            'password'        => 'required|string|min:8|max:255',
        ]);

        $server = Server::where('tenant_id', $tenantId)->findOrFail($data['server_id']);

        try {
            (new WhmService($server))->changeFtpPassword($data['cpanel_username'], $data['user'], $data['password']);
        } catch (WhmApiException $e) {
            return response()->json(['message' => 'Server rejected the request: ' . $e->getMessage()], 422);
        }

        return response()->json(['message' => 'FTP password changed.']);
    }

    public function destroyFtpAccount(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'server_id'       => ['required', 'uuid', Rule::exists('servers', 'id')->where('tenant_id', $tenantId)],
            'cpanel_username' => 'required|string|max:64',
            'user'            => 'required|string|max:255',
            'destroy_files'   => 'sometimes|boolean',
        ]);

        $server = Server::where('tenant_id', $tenantId)->findOrFail($data['server_id']);

        try {
            (new WhmService($server))->deleteFtpAccount($data['cpanel_username'], $data['user'], (bool) ($data['destroy_files'] ?? false));
        } catch (WhmApiException $e) {
            return response()->json(['message' => 'Server rejected the delete: ' . $e->getMessage()], 422);
        }

        return response()->json(['message' => 'FTP account deleted.']);
    }

    /**
     * Link a discovered-but-untracked cPanel account to a client: creates the
     * subscription it never had in MoBilling, then the hosting_accounts row
     * pointing at it. No WHM call — the account already exists on the server.
     */
    public function import(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'server_id'          => ['required', 'uuid', Rule::exists('servers', 'id')->where('tenant_id', $tenantId)],
            'cpanel_username'    => 'required|string|max:64',
            'domain'             => 'required|string|max:255',
            'client_id'          => ['required', 'uuid', Rule::exists('clients', 'id')->where('tenant_id', $tenantId)],
            'product_service_id' => ['required', 'uuid', Rule::exists('product_services', 'id')->where('tenant_id', $tenantId)],
        ]);

        $exists = HostingAccount::withoutGlobalScopes()
            ->where('server_id', $data['server_id'])
            ->where('cpanel_username', $data['cpanel_username'])
            ->exists();
        if ($exists) {
            return response()->json(['message' => 'This cPanel account is already imported.'], 422);
        }

        $client = Client::withoutGlobalScopes()->findOrFail($data['client_id']);
        $product = ProductService::withoutGlobalScopes()->findOrFail($data['product_service_id']);

        // Live status/package straight from the server, so the imported
        // record isn't just guessed from the discover-list snapshot.
        $server = Server::findOrFail($data['server_id']);
        $summary = [];
        try {
            $summary = (new WhmService($server))->accountSummary($data['cpanel_username']);
        } catch (WhmApiException) {
            // best-effort — fall back to the product's package/active status
        }

        $subscription = ClientSubscription::create([
            'tenant_id'          => $tenantId,
            'client_id'          => $client->id,
            'product_service_id' => $product->id,
            'label'              => $data['domain'],
            'quantity'           => 1,
            'start_date'         => now(),
            'status'             => ($summary['suspended'] ?? false) ? 'suspended' : 'active',
            'metadata'           => ['imported_existing' => true],
        ]);

        $hostingAccount = HostingAccount::create([
            'tenant_id'              => $tenantId,
            'client_subscription_id' => $subscription->id,
            'server_id'              => $data['server_id'],
            'domain'                 => $data['domain'],
            'cpanel_username'        => $data['cpanel_username'],
            'package'                => $summary['plan'] ?? $product->cpanel_package,
            'status'                 => ($summary['suspended'] ?? false) ? 'suspended' : 'active',
            'last_synced_at'         => now(),
            'meta'                   => ['adopted_existing' => true],
        ]);

        return response()->json([
            'data'    => $hostingAccount,
            'message' => "{$data['domain']} imported and linked to {$client->name}.",
        ], 201);
    }

    public function index(Request $request)
    {
        $query = HostingAccount::with(['server:id,name,hostname', 'subscription.client:id,name'])
            ->orderByDesc('created_at');

        if ($request->filled('status')) $query->where('status', $request->status);
        if ($request->filled('server_id')) $query->where('server_id', $request->server_id);
        if ($request->filled('search')) {
            $s = $request->search;
            $query->where(fn ($q) => $q
                ->where('domain', 'like', "%{$s}%")
                ->orWhere('cpanel_username', 'like', "%{$s}%"));
        }

        $paginated = $query->paginate($request->get('per_page', 20));

        // Domain registration expiry — no FK to `domains`, matched by name
        // (same convention used throughout the hosting integration).
        $domainNames = $paginated->getCollection()->pluck('domain')->filter()->unique()->values();
        $domainExpiry = Domain::whereIn('name', $domainNames)->pluck('expires_at', 'name');

        // Most recent invoice generated for this subscription's renewal —
        // surfaces the exact gap staff spotted: an account expires (or is
        // about to) with no invoice ever raised for it, because the
        // recurring-invoice job silently skipped it.
        $subIds = $paginated->getCollection()->pluck('subscription.id')->filter()->unique()->values();
        $latestLogBySub = \App\Models\RecurringInvoiceLog::whereIn('client_subscription_id', $subIds)
            ->with('document:id,document_number,status,date,due_date')
            ->orderByDesc('invoice_created_at')
            ->get()
            ->unique('client_subscription_id')
            ->keyBy('client_subscription_id');

        $paginated->getCollection()->transform(function ($account) use ($domainExpiry, $latestLogBySub) {
            $account->domain_expires_at = $domainExpiry->get($account->domain)?->toDateString();
            $log = $account->subscription ? $latestLogBySub->get($account->subscription->id) : null;
            $account->latest_invoice = $log?->document ? [
                'id'              => $log->document->id,
                'document_number' => $log->document->document_number,
                'status'          => $log->document->status,
                'date'            => $log->document->date?->toDateString(),
            ] : null;
            return $account;
        });

        return response()->json(['data' => $paginated]);
    }

    /** Manually provision the hosting account for a subscription. */
    public function provision(ClientSubscription $clientSubscription)
    {
        if ($clientSubscription->hostingAccount()->exists()) {
            return response()->json(['message' => 'Subscription already has a hosting account.'], 422);
        }
        if ($clientSubscription->productService?->provisioning_type !== 'whm_cpanel') {
            return response()->json(['message' => 'This product is not configured for WHM provisioning.'], 422);
        }

        ProvisionHostingAccount::dispatch($clientSubscription);

        return response()->json(['message' => 'Provisioning started.'], 202);
    }

    /**
     * The hosting account's real hosting-PLAN subscription — not just
     * $hostingAccount->subscription, which has repeatedly been found
     * pointing at the wrong subscription for this domain (a Backup add-on,
     * a Domain Registration, or a stale cancelled one — see
     * PlanChangeService's own fallback for the first instance of this).
     * Prefers the active "Web Hosting" subscription matched by domain
     * name; falls back to the direct relation if none matches.
     */
    private function hostingPlanSubscription(HostingAccount $hostingAccount): ?ClientSubscription
    {
        $byDomain = ClientSubscription::withoutGlobalScopes()
            ->whereNull('deleted_at')
            ->where('tenant_id', $hostingAccount->tenant_id)
            ->where('label', $hostingAccount->domain)
            ->where('status', 'active')
            ->whereHas('productService', fn ($q) => $q->where('category', 'Web Hosting'))
            ->with('productService')
            ->first();

        return $byDomain ?? $hostingAccount->subscription;
    }

    /** Price preview for a manual "generate invoice" action — computes, doesn't create anything. */
    public function invoicePreview(HostingAccount $hostingAccount)
    {
        $sub = $this->hostingPlanSubscription($hostingAccount);
        if (!$sub) {
            return response()->json(['message' => 'No hosting-plan subscription found for this domain.'], 422);
        }

        try {
            $preview = app(\App\Services\RecurringInvoiceService::class)->previewForSubscription($sub);
        } catch (\Throwable $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->json(['data' => $preview + [
            'product_name' => $sub->productService->name,
            'client_name'  => $sub->client()->withoutGlobalScopes()->value('name'),
        ]]);
    }

    /** Manually generate the renewal invoice this domain is missing. */
    public function generateInvoice(HostingAccount $hostingAccount)
    {
        $sub = $this->hostingPlanSubscription($hostingAccount);
        if (!$sub) {
            return response()->json(['message' => 'No hosting-plan subscription found for this domain.'], 422);
        }

        try {
            $document = app(\App\Services\RecurringInvoiceService::class)->generateForSubscription($sub);
        } catch (\Throwable $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->json([
            'data'    => ['id' => $document->id, 'document_number' => $document->document_number, 'total' => (float) $document->total],
            'message' => "Invoice {$document->document_number} created.",
        ], 201);
    }

    public function suspend(HostingAccount $hostingAccount)
    {
        SuspendHostingAccount::dispatch($hostingAccount, 'Suspended by admin');
        $this->notifyStatusChange($hostingAccount, suspended: true);
        return response()->json(['message' => 'Suspension started.'], 202);
    }

    public function unsuspend(HostingAccount $hostingAccount)
    {
        ReactivateHostingAccount::dispatch($hostingAccount);
        $this->notifyStatusChange($hostingAccount, suspended: false);
        return response()->json(['message' => 'Unsuspension started.'], 202);
    }

    /** Tell the client about a manual suspend/restore (auto flows notify elsewhere). */
    private function notifyStatusChange(HostingAccount $hostingAccount, bool $suspended): void
    {
        try {
            $client = $hostingAccount->subscription?->client;
            $tenant = \App\Models\Tenant::withoutGlobalScopes()->find($hostingAccount->tenant_id);
            if ($client && $tenant && ($client->email || $client->phone)) {
                $client->notify(new \App\Notifications\HostingStatusChangedNotification($hostingAccount, $tenant, $suspended));
            }
        } catch (\Throwable $e) {
            \Illuminate\Support\Facades\Log::warning('Hosting status notice failed', ['error' => $e->getMessage()]);
        }
    }

    public function terminate(HostingAccount $hostingAccount)
    {
        TerminateHostingAccount::dispatch($hostingAccount);
        return response()->json(['message' => 'Termination started.'], 202);
    }

    public function changePackage(Request $request, HostingAccount $hostingAccount)
    {
        $data = $request->validate(['package' => 'required|string|max:255']);
        ChangeHostingPackage::dispatch($hostingAccount, $data['package']);
        return response()->json(['message' => 'Package change started.'], 202);
    }

    /** One-time cPanel SSO URL. */
    public function sso(HostingAccount $hostingAccount)
    {
        try {
            $url = (new WhmService($hostingAccount->server))
                ->forAccount($hostingAccount->id)
                ->ssoUrl($hostingAccount->cpanel_username);

            return response()->json(['url' => $url]);
        } catch (WhmApiException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }
    }

    public function logs(HostingAccount $hostingAccount)
    {
        return response()->json(['data' => $hostingAccount->logs()->limit(50)->get()]);
    }
}
