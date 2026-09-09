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

    /** @return array<int, array<string, mixed>> */
    private function call(string $action, string $path, array $equals = [], array $sensitiveKeys = []): array
    {
        $logParams = collect($equals)->except($sensitiveKeys)->all();

        try {
            $query = new Query($path);
            foreach ($equals as $key => $value) {
                $query->equal($key, (string) $value);
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
     * Create a hotspot user with a time-limited profile. $limitUptimeSeconds
     * is written as RouterOS's own "1d2h3m4s" duration syntax on the
     * "limit-uptime" field — the router itself disables the user once that
     * much time has elapsed, no MoBilling-side timer needed.
     */
    public function createHotspotUser(string $username, string $password, ?string $profile, int $limitUptimeSeconds): void
    {
        $this->call('hotspot_user_add', '/ip/hotspot/user/add', array_filter([
            'name'          => $username,
            'password'      => $password,
            'profile'       => $profile,
            'limit-uptime'  => $this->formatDuration($limitUptimeSeconds),
        ]), sensitiveKeys: ['password']);
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
}
