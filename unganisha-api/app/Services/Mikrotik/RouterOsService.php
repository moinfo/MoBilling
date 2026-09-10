<?php

namespace App\Services\Mikrotik;

use App\Exceptions\MikrotikApiException;
use App\Models\MikrotikLog;
use App\Models\MikrotikRouter;
use RouterOS\Client;
use RouterOS\Query;

/**
 * RouterOS API client for one MikroTik router (docs/... none yet — this is
 * the first integration of its kind). Unlike WhmService/FredHttpDriver
 * there is no HTTP endpoint here — RouterOS speaks its own binary protocol
 * over a persistent TCP socket (evilfreelancer/routeros-api-php). Mirrors
 * WhmService's shape otherwise: one call() wrapper that logs every
 * request/response (secrets stripped) and throws a dedicated exception on
 * failure, so callers never need to know the transport details.
 */
class RouterOsService
{
    private ?Client $client = null;

    public function __construct(private MikrotikRouter $router) {}

    private function client(): Client
    {
        if ($this->client) {
            return $this->client;
        }

        return $this->client = new Client([
            'host'    => $this->router->host,
            'user'    => $this->router->username,
            'pass'    => $this->router->password,
            'port'    => $this->router->api_port,
            'ssl'     => (bool) $this->router->use_tls,
            'timeout' => 10,
            'attempts' => 1,
        ]);
    }

    /**
     * $equals words become `=key=value` (RouterOS's syntax for add/set
     * attribute assignment) for every command EXCEPT /print, which needs
     * `?key=value` query words to filter instead — using `=` there doesn't
     * filter at all and RouterOS silently returns an error-shaped reply
     * ("unknown parameter name") that this library doesn't surface as an
     * exception, so a caller filtering /print by, say, `name` got back a
     * single bogus non-array "row" instead of a real match or a clean
     * empty result. Every /print call in this class filters by some field
     * (hotspot_user_print by name, hotspot_active_print by user), so this
     * matters everywhere, not just one call site.
     *
     * @return array<int, array<string, mixed>>
     */
    private function call(string $action, string $path, array $equals = [], array $sensitiveKeys = []): array
    {
        $logParams = collect($equals)->except($sensitiveKeys)->all();
        $isPrint = str_ends_with($path, '/print');

        try {
            $query = new Query($path);
            foreach ($equals as $key => $value) {
                $isPrint ? $query->where($key, (string) $value) : $query->equal($key, (string) $value);
            }

            $result = $this->client()->query($query)->read();

            $this->log($action, $logParams, $result, true, null);

            return $result;
        } catch (\Throwable $e) {
            $this->log($action, $logParams, null, false, $e->getMessage());
            throw new MikrotikApiException($action, $e->getMessage());
        }
    }

    private function log(string $action, array $request, ?array $response, bool $ok, ?string $error): void
    {
        try {
            MikrotikLog::create([
                'tenant_id'          => $this->router->tenant_id,
                'mikrotik_router_id' => $this->router->id,
                'action'             => $action,
                'request'            => $request ?: null,
                'response'           => $response ? json_decode(mb_substr(json_encode($response), 0, 8000), true) : null,
                'status'             => $ok ? 'success' : 'failed',
                'error'              => $error,
            ]);
        } catch (\Throwable) {
            // auditing must never break provisioning
        }
    }

    /** Confirm the router is reachable and the hotspot module answers. */
    public function testConnection(): array
    {
        $this->call('test_connection', '/ip/hotspot/user/print');
        return ['ok' => true, 'message' => 'Connected successfully.'];
    }

    /**
     * Create a hotspot user. $limitUptimeSeconds is written as RouterOS's
     * own "1d2h3m4s" duration syntax on the "limit-uptime" field — the
     * router itself disables the user once that much *connected* time has
     * elapsed (not wall-clock time — buying in advance for later use costs
     * nothing), no MoBilling-side timer needed. Null means no time limit
     * (a pure data-cap voucher, good until $limitBytesTotal runs out).
     */
    public function createHotspotUser(string $username, string $password, ?string $profile, ?int $limitUptimeSeconds, ?int $limitBytesTotal = null): void
    {
        $this->call('hotspot_user_add', '/ip/hotspot/user/add', array_filter([
            'name'              => $username,
            'password'          => $password,
            'profile'           => $profile,
            'limit-uptime'      => $limitUptimeSeconds !== null ? $this->formatDuration($limitUptimeSeconds) : null,
            'limit-bytes-total' => $limitBytesTotal,
        ]), sensitiveKeys: ['password']);
    }

    /**
     * Cumulative usage so far for a hotspot user — persists across
     * reconnects, since it lives on the `/ip hotspot user` record itself,
     * not a per-session counter. `uptime_seconds` in particular is
     * connected-*time*, not wall-clock time since purchase: a "1 day" quota
     * only starts running down once the customer actually logs in, so
     * buying in advance for later use costs them nothing. Null if the user
     * no longer exists on the router (e.g. manually removed).
     */
    public function getHotspotUserUsage(string $username): ?array
    {
        $rows = $this->call('hotspot_user_print', '/ip/hotspot/user/print', ['name' => $username]);
        if (empty($rows)) {
            return null;
        }

        return [
            'bytes_in'       => (int) ($rows[0]['bytes-in'] ?? 0),
            'bytes_out'      => (int) ($rows[0]['bytes-out'] ?? 0),
            'uptime_seconds' => $this->parseDuration($rows[0]['uptime'] ?? ''),
        ];
    }

    public function removeHotspotUser(string $username): void
    {
        $rows = $this->call('hotspot_user_print', '/ip/hotspot/user/print', ['name' => $username]);
        $id = $rows[0]['.id'] ?? null;
        if (!$id) {
            return; // already gone — nothing to remove
        }

        $this->call('hotspot_user_remove', '/ip/hotspot/user/remove', ['.id' => $id]);
    }

    /**
     * Blocks a voucher immediately — disables future logins AND kicks any
     * session that's connected right now (disabling the user alone doesn't
     * drop an already-authenticated session). Keeps the user record intact
     * (vs. removeHotspotUser) so it can be un-blocked later without losing
     * its usage history/limits.
     */
    public function disableHotspotUser(string $username): void
    {
        $rows = $this->call('hotspot_user_print', '/ip/hotspot/user/print', ['name' => $username]);
        $id = $rows[0]['.id'] ?? null;
        if ($id) {
            $this->call('hotspot_user_disable', '/ip/hotspot/user/set', ['.id' => $id, 'disabled' => 'yes']);
        }

        $active = $this->call('hotspot_active_print', '/ip/hotspot/active/print', ['user' => $username]);
        foreach ($active as $session) {
            if (!empty($session['.id'])) {
                $this->call('hotspot_active_remove', '/ip/hotspot/active/remove', ['.id' => $session['.id']]);
            }
        }
    }

    public function enableHotspotUser(string $username): void
    {
        $rows = $this->call('hotspot_user_print', '/ip/hotspot/user/print', ['name' => $username]);
        $id = $rows[0]['.id'] ?? null;
        if (!$id) {
            return;
        }

        $this->call('hotspot_user_enable', '/ip/hotspot/user/set', ['.id' => $id, 'disabled' => 'no']);
    }

    private function formatDuration(int $seconds): string
    {
        $days = intdiv($seconds, 86400);
        $seconds %= 86400;
        $hours = intdiv($seconds, 3600);
        $seconds %= 3600;
        $minutes = intdiv($seconds, 60);
        $seconds %= 60;

        return "{$days}d{$hours}h{$minutes}m{$seconds}s";
    }

    /**
     * Inverse of formatDuration(), tolerant of both RouterOS duration
     * formats seen in the wild: letter-delimited ("1d2h3m4s", any subset)
     * and colon-delimited ("3d05:14:32" / "05:14:32"). Unparseable or
     * empty input (e.g. a user who's never connected, so RouterOS omits
     * the field) returns 0.
     */
    private function parseDuration(string $value): int
    {
        $value = trim($value);
        if ($value === '') {
            return 0;
        }

        if (preg_match('/^(?:(\d+)d)?(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$/', $value, $m) && array_sum(array_map('intval', array_slice($m, 1))) > 0) {
            return ((int) ($m[1] ?? 0) * 86400) + ((int) ($m[2] ?? 0) * 3600) + ((int) ($m[3] ?? 0) * 60) + (int) ($m[4] ?? 0);
        }

        if (preg_match('/^(?:(\d+)d)?(\d{1,2}):(\d{2}):(\d{2})$/', $value, $m)) {
            return ((int) ($m[1] ?? 0) * 86400) + ((int) $m[2] * 3600) + ((int) $m[3] * 60) + (int) $m[4];
        }

        return 0;
    }
}
