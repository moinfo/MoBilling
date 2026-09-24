<?php

namespace App\Services\Linode;

use App\Exceptions\LinodeApiException;
use App\Models\LinodeAccount;
use App\Models\LinodeAuditLog;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Http;

/**
 * Linode API v4 client for one tenant-owned LinodeAccount.
 *
 * The personal access token cannot be scoped per resource, so it can reach
 * every domain/instance in the Linode account: THIS APP is the isolation
 * layer (all models are tenant scoped). The token is only ever used as a
 * Bearer header — never logged, audited or returned.
 */
class LinodeService
{
    public const BASE_URL = 'https://api.linode.com/v4';
    public const NAMESERVERS = ['ns1.linode.com', 'ns2.linode.com', 'ns3.linode.com', 'ns4.linode.com', 'ns5.linode.com'];
    public const DOMAIN_TTLS = [0, 30, 120, 300, 3600, 7200, 14400, 28800, 57600, 86400, 172800, 345600, 604800, 1209600, 2419200];
    public const RECORD_TTLS = [0, 300, 3600, 7200, 14400, 28800, 57600, 86400, 172800, 345600, 604800, 1209600, 2419200];
    public const RECORD_TYPES = ['A', 'AAAA', 'CNAME', 'MX', 'TXT', 'SRV', 'CAA'];
    private const SECRET_KEYS = ['token', 'authorization', 'password', 'secret', 'api_token'];

    /** Tests set this false to skip real sleeping on 429. */
    public static bool $sleepOnRateLimit = true;
    private const MAX_RETRIES = 3;
    /** Paginated GETs are limited to 200/min by Linode: keep >= 350ms between them (~170/min). Tests set 0. */
    public static int $paginatedGapMs = 350;
    private static float $lastPaginatedAt = 0.0;

    public function __construct(private LinodeAccount $account) {}

    // ── validation helpers (static, no network) ──

    public static function validateDomainName(string $domain): string
    {
        $d = strtolower(trim($domain));
        if (!preg_match('/^(?=.{4,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/', $d)) {
            throw new \InvalidArgumentException('Invalid domain name. Use a name like example.co.tz (no http://, no trailing dot).');
        }
        return $d;
    }

    public static function validateTtl($ttl, array $allowed = self::DOMAIN_TTLS): int
    {
        if (!is_numeric($ttl) || !in_array((int) $ttl, $allowed, true)) {
            throw new \InvalidArgumentException('TTL must be one of: ' . implode(', ', $allowed) . ' seconds.');
        }
        return (int) $ttl;
    }

    /**
     * Validate + normalise a DNS record. $existing = current records of the zone
     * (used for duplicate/CNAME conflict checks). $ignoreId = record being edited.
     * @throws \InvalidArgumentException
     */
    public static function validateRecord(array $r, array $existing = [], ?string $ignoreId = null): array
    {
        $type = strtoupper(trim((string) ($r['type'] ?? '')));
        if (in_array($type, ['NS', 'SOA'], true)) {
            throw new \InvalidArgumentException("$type records are managed by Linode and cannot be changed here.");
        }
        if (!in_array($type, self::RECORD_TYPES, true)) {
            throw new \InvalidArgumentException('Record type must be one of: ' . implode(', ', self::RECORD_TYPES) . '.');
        }

        $name = strtolower(trim((string) ($r['name'] ?? '')));
        if ($name === '@') $name = '';
        if ($name !== '' && !preg_match('/^[a-z0-9_*]([a-z0-9_.*-]{0,251})$/', $name)) {
            throw new \InvalidArgumentException('Invalid record name. Use letters, digits, "-", "_", or leave empty for the root domain.');
        }
        if ($type === 'CNAME' && $name === '') {
            throw new \InvalidArgumentException('A CNAME cannot be set on the root domain (apex). Use an A record instead.');
        }

        $target = trim((string) ($r['target'] ?? ''));
        if ($target === '') {
            throw new \InvalidArgumentException('Target is required.');
        }
        switch ($type) {
            case 'A':
                if (!filter_var($target, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)) throw new \InvalidArgumentException('A record target must be an IPv4 address.');
                break;
            case 'AAAA':
                if (!filter_var($target, FILTER_VALIDATE_IP, FILTER_FLAG_IPV6)) throw new \InvalidArgumentException('AAAA record target must be an IPv6 address.');
                break;
            case 'CNAME':
            case 'MX':
            case 'SRV':
                $target = rtrim(strtolower($target), '.');
                if (!preg_match('/^(?=.{1,253}$)([a-z0-9_]([a-z0-9_-]{0,61}[a-z0-9_])?\.)*[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/', $target)) {
                    throw new \InvalidArgumentException("$type target must be a hostname.");
                }
                break;
            case 'TXT':
                if (strlen($target) > 2000) throw new \InvalidArgumentException('TXT value is too long.');
                break;
            case 'CAA':
                if (strlen($target) > 500) throw new \InvalidArgumentException('CAA value is too long.');
                break;
        }

        $out = ['type' => $type, 'name' => $name, 'target' => $target];

        $ttl = $r['ttl_sec'] ?? 0;
        $out['ttl_sec'] = self::validateTtl($ttl === null || $ttl === '' ? 0 : $ttl, self::RECORD_TTLS);

        if ($type === 'MX' || $type === 'SRV') {
            $p = $r['priority'] ?? null;
            if (!is_numeric($p) || $p < 0 || $p > 255) throw new \InvalidArgumentException('Priority (0-255) is required for MX/SRV records.');
            $out['priority'] = (int) $p;
        }
        if ($type === 'SRV') {
            foreach (['weight', 'port'] as $k) {
                $v = $r[$k] ?? null;
                if (!is_numeric($v) || $v < 0 || $v > 65535) throw new \InvalidArgumentException(ucfirst($k) . ' (0-65535) is required for SRV records.');
                $out[$k] = (int) $v;
            }
            foreach (['service', 'protocol'] as $k) {
                if (!empty($r[$k])) $out[$k] = (string) $r[$k];
            }
            if ($name === '') throw new \InvalidArgumentException('SRV records need a name.');
        }
        if ($type === 'CAA') {
            $tag = $r['tag'] ?? '';
            if (!in_array($tag, ['issue', 'issuewild', 'iodef'], true)) throw new \InvalidArgumentException('CAA tag must be issue, issuewild or iodef.');
            $out['tag'] = $tag;
        }

        foreach ($existing as $e) {
            if ($ignoreId !== null && (string) ($e['id'] ?? '') === $ignoreId) continue;
            $eType = strtoupper((string) ($e['type'] ?? ''));
            $eName = strtolower((string) ($e['name'] ?? ''));
            if ($eType === $type && $eName === $name && strtolower(rtrim((string) ($e['target'] ?? ''), '.')) === strtolower(rtrim($target, '.'))
                && ($type !== 'MX' || (int) ($e['priority'] ?? 0) === ($out['priority'] ?? 0))) {
                throw new \InvalidArgumentException('An identical record already exists.');
            }
            if ($eName === $name) {
                if ($type === 'CNAME' && $eType !== 'CNAME') {
                    throw new \InvalidArgumentException("A CNAME cannot share a name with an existing $eType record.");
                }
                if ($eType === 'CNAME' && $type !== 'CNAME') {
                    throw new \InvalidArgumentException('That name already has a CNAME record; a CNAME cannot coexist with other records.');
                }
            }
        }

        return $out;
    }

    // ── high-level operations ──

    /**
     * Probe both scopes we need. Returns ['status'=>active|invalid,'message'=>?string,'missing'=>[]].
     * 401 => invalid token. 403 => token valid but scope missing.
     */
    public function verifyToken(): array
    {
        $missing = [];
        foreach ([['/domains', 'domains:read_only'], ['/linode/instances', 'linodes:read_only']] as [$path, $scope]) {
            try {
                $this->request('GET', $path, ['page_size' => 25]);
            } catch (LinodeApiException $e) {
                if ($e->httpStatus === 401) {
                    return ['status' => 'invalid', 'message' => $e->getMessage(), 'missing' => []];
                }
                if ($e->httpStatus === 403) {
                    $missing[] = $scope;
                    continue;
                }
                throw $e;
            }
        }
        if ($missing) {
            return ['status' => 'active', 'message' => 'Token is valid but is missing scope(s): ' . implode(', ', $missing) . '.', 'missing' => $missing];
        }
        return ['status' => 'active', 'message' => null, 'missing' => []];
    }

    public function listInstances(): array
    {
        return $this->paginate('/linode/instances');
    }

    public function listDomains(): array
    {
        return $this->paginate('/domains');
    }

    public function createDomain(string $domain, string $soaEmail, ?int $ttl = null): array
    {
        $domain = self::validateDomainName($domain);
        if (!filter_var($soaEmail, FILTER_VALIDATE_EMAIL)) {
            throw new \InvalidArgumentException('A valid SOA email is required.');
        }
        $body = ['domain' => $domain, 'type' => 'master', 'soa_email' => $soaEmail];
        if ($ttl !== null) $body['ttl_sec'] = self::validateTtl($ttl);

        return $this->request('POST', '/domains', $body, 'domain.create', $domain);
    }

    public function listRecords(string|int $domainId): array
    {
        return $this->paginate("/domains/{$domainId}/records");
    }

    public function createRecord(string|int $domainId, array $record): array
    {
        $clean = self::validateRecord($record, $this->listRecords($domainId));
        return $this->request('POST', "/domains/{$domainId}/records", $clean, 'record.create', "domain:{$domainId}");
    }

    public function updateRecord(string|int $domainId, string|int $recordId, array $record): array
    {
        $existing = $this->listRecords($domainId);
        $current = collect($existing)->firstWhere('id', (int) $recordId);
        if (!$current) throw new \InvalidArgumentException('Record not found.');
        if (in_array(strtoupper($current['type'] ?? ''), ['NS', 'SOA'], true)) {
            throw new \InvalidArgumentException(strtoupper($current['type']) . ' records are managed by Linode and cannot be changed here.');
        }
        $clean = self::validateRecord($record, $existing, (string) $recordId);
        return $this->request('PUT', "/domains/{$domainId}/records/{$recordId}", $clean, 'record.update', "domain:{$domainId}/record:{$recordId}");
    }

    public function deleteRecord(string|int $domainId, string|int $recordId): void
    {
        $current = collect($this->listRecords($domainId))->firstWhere('id', (int) $recordId);
        if ($current && in_array(strtoupper($current['type'] ?? ''), ['NS', 'SOA'], true)) {
            throw new \InvalidArgumentException(strtoupper($current['type']) . ' records are managed by Linode and cannot be changed here.');
        }
        $this->request('DELETE', "/domains/{$domainId}/records/{$recordId}", [], 'record.delete', "domain:{$domainId}/record:{$recordId}");
    }

    /** A for the root ("") and www pointing at the server; identical existing ones are skipped. */
    public function createStandardWebRecords(string|int $domainId, string $ipv4, int $ttl = 0): array
    {
        if (!filter_var($ipv4, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)) {
            throw new \InvalidArgumentException('The chosen server has no IPv4 address.');
        }
        $created = [];
        foreach (['', 'www'] as $name) {
            try {
                $created[] = $this->createRecord($domainId, ['type' => 'A', 'name' => $name, 'target' => $ipv4, 'ttl_sec' => $ttl]);
            } catch (\InvalidArgumentException $e) {
                if (!str_contains($e->getMessage(), 'identical')) throw $e;
            }
        }
        return $created;
    }

    // ── power actions (linodes:read_write) ──

    public const POWER_ACTIONS = ['reboot', 'shutdown', 'boot'];
    /** status required before each action */
    public const POWER_REQUIRES = ['reboot' => 'running', 'shutdown' => 'running', 'boot' => 'offline'];
    public const BUSY_STATUSES = ['booting', 'rebooting', 'shutting_down', 'provisioning', 'migrating', 'rebuilding', 'cloning', 'restoring', 'stopped_pending', 'resizing', 'deleting'];
    public const POWER_OPTIMISTIC = ['reboot' => 'rebooting', 'shutdown' => 'shutting_down', 'boot' => 'booting'];

    /** Live status of one instance (GET /linode/instances/{id}). */
    public function getInstance(string|int $instanceId): array
    {
        return $this->request('GET', "/linode/instances/" . (int) $instanceId);
    }

    /**
     * Refuses (\DomainException) unless the LIVE status allows the action, then issues exactly one POST.
     * Returns the live status that was seen before acting.
     */
    public function powerAction(string|int $instanceId, string $action): string
    {
        if (!in_array($action, self::POWER_ACTIONS, true)) {
            throw new \InvalidArgumentException('Unknown power action.');
        }
        $id = (int) $instanceId;
        $live = (string) ($this->getInstance($id)['status'] ?? '');
        if (in_array($live, self::BUSY_STATUSES, true)) {
            throw new \DomainException("The server is busy right now (status: $live). Wait until it is running or offline, then try again.");
        }
        $need = self::POWER_REQUIRES[$action];
        if ($live !== $need) {
            throw new \DomainException(match ($action) {
                'boot' => "Cannot boot: the server is '$live', not offline.",
                default => "Cannot $action: the server is '$live', not running.",
            });
        }
        try {
            $this->request('POST', "/linode/instances/{$id}/{$action}");
        } catch (LinodeApiException $e) {
            if ($e->httpStatus === 403) {
                throw new LinodeApiException('The Linode token needs linodes: read/write to control servers. Create a token with that scope in Linode Cloud Manager and rotate it on the Accounts tab.', 403, $e->errors);
            }
            if ($e->httpStatus === 400) {
                $why = collect($e->errors)->pluck('reason')->filter()->implode('; ');
                throw new LinodeApiException('Linode refused the action' . (stripos($why, 'busy') !== false ? ': the server is busy with another operation. Try again in a minute.' : ($why ? ": $why" : '.')), 400, $e->errors);
            }
            throw $e;
        }
        return $live;
    }

    // ── transport ──

    private function paginate(string $path): array
    {
        $all = [];
        $page = 1;
        do {
            if (self::$paginatedGapMs > 0) {
                $wait = self::$lastPaginatedAt + self::$paginatedGapMs / 1000 - microtime(true);
                if ($wait > 0) usleep((int) ($wait * 1e6));
            }
            $json = $this->request('GET', $path, ['page' => $page, 'page_size' => 100]);
            self::$lastPaginatedAt = microtime(true);
            $all = array_merge($all, $json['data'] ?? []);
            $pages = (int) ($json['pages'] ?? 1);
            $page++;
        } while ($page <= $pages && $page <= 50);

        return $all;
    }

    private function request(string $method, string $path, array $params = [], ?string $auditAction = null, ?string $target = null): array
    {
        $attempt = 0;
        $status = null;
        try {
            while (true) {
                $http = Http::withToken($this->account->token)->acceptJson()->timeout(20)->connectTimeout(10);
                $url = self::BASE_URL . $path;
                try {
                    $res = match ($method) {
                        'GET'    => $http->get($url, $params),
                        'POST'   => $http->post($url, $params),
                        'PUT'    => $http->put($url, $params),
                        'DELETE' => $http->delete($url),
                    };
                } catch (ConnectionException $e) {
                    throw new LinodeApiException('Could not reach Linode (network error or timeout). Try again shortly.');
                }
                $status = $res->status();

                if ($status === 429 && $attempt < self::MAX_RETRIES) {
                    $attempt++;
                    if (self::$sleepOnRateLimit) sleep(min(max((int) $res->header('Retry-After'), 1), 20));
                    continue;
                }
                break;
            }

            if ($res->successful()) {
                $this->audit($auditAction, $target, $params, $status, null);
                return $res->json() ?? [];
            }
            throw $this->mapError($status, $res->json() ?? [], $method, $path);
        } catch (LinodeApiException $e) {
            $this->audit($auditAction, $target, $params, $e->httpStatus ?: $status, $e->getMessage());
            throw $e;
        }
    }

    private function mapError(int $status, array $json, string $method, string $path): LinodeApiException
    {
        $reasons = collect($json['errors'] ?? [])->map(fn ($e) => trim(($e['field'] ?? '') ? "{$e['field']}: {$e['reason']}" : ($e['reason'] ?? '')))->filter()->implode('; ');

        $msg = match (true) {
            $status === 401 => 'Linode rejected the token (invalid, expired or revoked). Create a new token in Linode Cloud Manager and rotate it here.',
            $status === 403 => 'The Linode token does not have permission for this action. Required scope: ' . $this->scopeFor($method, $path) . '. Create a token with that scope and rotate it here.',
            $status === 404 => 'Not found on Linode' . ($reasons ? ": $reasons" : '.'),
            $status === 429 => 'Linode rate limit reached. Wait a minute and try again.',
            $status >= 500  => 'Linode is having problems (HTTP ' . $status . '). Try again later.',
            default         => 'Linode error: ' . ($reasons ?: "HTTP $status"),
        };

        return new LinodeApiException($msg, $status, $json['errors'] ?? []);
    }

    private function scopeFor(string $method, string $path): string
    {
        $level = $method === 'GET' ? 'read_only' : 'read_write';
        $group = str_starts_with($path, '/linode') ? 'linodes' : (str_starts_with($path, '/domains') ? 'domains' : 'account');
        return "{$group}:{$level}";
    }

    private function audit(?string $action, ?string $target, array $params, ?int $status, ?string $error): void
    {
        if ($action === null) return; // reads are not audited

        try {
            LinodeAuditLog::create([
                'tenant_id'         => $this->account->tenant_id,
                'user_id'           => auth()->id(),
                'linode_account_id' => $this->account->id,
                'action'            => $action,
                'target'            => $target,
                'request'           => $this->scrub($params),
                'response_status'   => $status,
                'error'             => $error ? mb_substr($error, 0, 250) : null,
            ]);
        } catch (\Throwable $e) {
            \Log::warning('Linode audit write failed', ['error' => $e->getMessage()]);
        }
    }

    private function scrub(array $params): array
    {
        return collect($params)->reject(fn ($v, $k) => in_array(strtolower((string) $k), self::SECRET_KEYS, true))->all();
    }
}
