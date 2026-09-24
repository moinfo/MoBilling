<?php

namespace App\Services\Registrar;

use App\Contracts\RegistrarDriver;
use App\Exceptions\NameComApiException;
use App\Exceptions\RegistrarApiException;
use App\Models\NameComAccount;
use App\Models\NameComAuditLog;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Http;

/**
 * Name.com Core API v1 driver — NAMESERVER MANAGEMENT ONLY.
 *
 * Deliberately narrow: the HTTP wrapper only ever sends
 *   GET  /core/v1/domains            (list)
 *   GET  /core/v1/domains/{name}     (details)
 *   POST /core/v1/domains/{name}:setNameservers
 * Everything else (register, renew, transfer, delete, contacts, DNS records...)
 * is refused before any network call. The token is only used as HTTP Basic
 * credentials: never logged, audited or returned.
 */
class NameComDriver implements RegistrarDriver
{
    public const BASE_URL = 'https://api.name.com';
    public const SANDBOX_URL = 'https://api.dev.name.com';
    public const MIN_NAMESERVERS = 2;
    public const MAX_NAMESERVERS = 13;
    private const MAX_RETRIES = 3;
    private const PER_PAGE = 250;
    private const MAX_PAGES = 40;

    /** Tests set this false to skip real sleeping on 429. */
    public static bool $sleepOnRateLimit = true;
    /** Name.com allows 20 req/s; keep >= 100ms between paginated GETs. Tests set 0. */
    public static int $paginatedGapMs = 100;
    private static float $lastPaginatedAt = 0.0;

    public function __construct(private NameComAccount $account) {}

    // ── validation (no network) ──

    /** @return string[] normalised (lowercase, no trailing dot) @throws \InvalidArgumentException */
    public static function validateNameservers(array $ns): array
    {
        $out = [];
        foreach ($ns as $n) {
            $h = rtrim(strtolower(trim((string) $n)), '.');
            if ($h === '') continue;
            if (filter_var($h, FILTER_VALIDATE_IP)) {
                throw new \InvalidArgumentException("\"$h\" is an IP address - nameservers must be hostnames like ns1.example.com.");
            }
            if (!preg_match('/^(?=.{4,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/', $h)) {
                throw new \InvalidArgumentException("\"$h\" is not a valid hostname.");
            }
            $out[] = $h;
        }
        if (count($out) !== count(array_unique($out))) {
            throw new \InvalidArgumentException('Nameservers must be different from each other.');
        }
        if (count($out) < self::MIN_NAMESERVERS || count($out) > self::MAX_NAMESERVERS) {
            throw new \InvalidArgumentException('Provide between ' . self::MIN_NAMESERVERS . ' and ' . self::MAX_NAMESERVERS . ' nameservers.');
        }
        return $out;
    }

    public static function validateDomainName(string $name): string
    {
        $d = strtolower(trim($name));
        if (!preg_match('/^(?=.{4,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/', $d)) {
            throw new \InvalidArgumentException('Invalid domain name.');
        }
        return $d;
    }

    // ── read operations ──

    /** Cheap credential check: one read call. */
    public function verify(): array
    {
        $this->request('GET', '/core/v1/domains', ['perPage' => 1, 'page' => 1]);
        return ['status' => 'active', 'message' => null];
    }

    /** All domains of the account (paced, paginated). */
    public function listDomains(): array
    {
        $all = [];
        $page = 1;
        do {
            if (self::$paginatedGapMs > 0) {
                $wait = self::$lastPaginatedAt + self::$paginatedGapMs / 1000 - microtime(true);
                if ($wait > 0) usleep((int) ($wait * 1e6));
            }
            $json = $this->request('GET', '/core/v1/domains', ['perPage' => self::PER_PAGE, 'page' => $page, 'includeRenewalPrice' => 'false']);
            self::$lastPaginatedAt = microtime(true);
            $all = array_merge($all, $json['domains'] ?? []);
            $next = (int) ($json['nextPage'] ?? 0);
            $page = $next > $page ? $next : 0;
        } while ($page > 0 && $page <= self::MAX_PAGES);

        return $all;
    }

    public function getDomain(string $domain): array
    {
        return $this->request('GET', '/core/v1/domains/' . self::validateDomainName($domain));
    }

    /** @return string[] live nameservers */
    public function nameservers(string $domain): array
    {
        return self::extractNameservers($this->getDomain($domain));
    }

    public static function extractNameservers(array $info): array
    {
        return collect($info['nameservers'] ?? [])->map(fn ($n) => strtolower(trim((string) $n)))->filter()->values()->all();
    }

    // ── the one write ──

    /**
     * Exactly one POST to :setNameservers. $from/$actor are only for the audit row.
     * @param string[] $nameservers already validated
     */
    public function setNameservers(string $domain, array $nameservers, array $from = [], array $actor = []): array
    {
        $domain = self::validateDomainName($domain);
        $nameservers = self::validateNameservers($nameservers);

        return $this->request(
            'POST', "/core/v1/domains/{$domain}:setNameservers", [], ['nameservers' => $nameservers],
            'nameservers.set', $domain, ['from' => $from, 'to' => $nameservers] + $actor,
        );
    }

    // ── RegistrarDriver contract: only info() is meaningful here ──

    public function info(string $domain): array
    {
        $d = $this->getDomain($domain);
        return [
            'ex_date'     => substr((string) ($d['expireDate'] ?? ''), 0, 10),
            'cr_date'     => substr((string) ($d['createDate'] ?? ''), 0, 10),
            'nameservers' => self::extractNameservers($d),
            'locked'      => $d['locked'] ?? null,
            'autorenew'   => $d['autorenewEnabled'] ?? null,
        ];
    }

    public function updateDomain(string $domain, array $changes): array
    {
        if (array_keys($changes) !== ['nameservers']) {
            throw new RegistrarApiException('update', 'Only nameservers can be changed through Name.com.');
        }
        return $this->setNameservers($domain, $changes['nameservers']);
    }

    public function check(string $domain): array
    {
        throw new RegistrarApiException('check', 'Availability checks are not supported for Name.com.');
    }

    public function credit(): array
    {
        return [];
    }

    public function register(string $domain, int $years = 1, array $nameservers = []): array
    {
        throw new RegistrarApiException('register', 'Registration through Name.com is not enabled.');
    }

    public function renew(string $domain, int $years = 1): array
    {
        throw new RegistrarApiException('renew', 'Renewal through Name.com is not enabled.');
    }

    public function transferIn(string $domain, string $authInfo): array
    {
        throw new RegistrarApiException('transfer', 'Transfers through Name.com are not enabled.');
    }

    // ── transport ──

    /** Allow-list: refuses anything but the three permitted calls BEFORE touching the network. */
    public static function assertAllowed(string $method, string $path): void
    {
        $m = strtoupper($method);
        $ok = ($m === 'GET' && ($path === '/core/v1/domains' || preg_match('#^/core/v1/domains/[a-z0-9.-]+$#', $path)))
            || ($m === 'POST' && preg_match('#^/core/v1/domains/[a-z0-9.-]+:setNameservers$#', $path));
        if (!$ok) {
            throw new NameComApiException('This request is not permitted: only reading domains and setting nameservers is enabled for Name.com.');
        }
    }

    private function request(string $method, string $path, array $query = [], array $body = [], ?string $auditAction = null, ?string $target = null, array $auditRequest = []): array
    {
        self::assertAllowed($method, $path);
        $method = strtoupper($method);

        $sandbox = $this->account->is_sandbox;
        $user = $this->account->username . ($sandbox ? '-test' : '');
        $url = ($sandbox ? self::SANDBOX_URL : self::BASE_URL) . $path;
        $attempt = 0;
        $status = null;

        try {
            while (true) {
                $http = Http::withBasicAuth($user, (string) $this->account->token)->acceptJson()->timeout(20)->connectTimeout(10);
                try {
                    $res = $method === 'GET' ? $http->get($url, $query) : $http->post($url, $body);
                } catch (ConnectionException) {
                    throw new NameComApiException('Could not reach Name.com (network error or timeout). Try again shortly.');
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
                $this->audit($auditAction, $target, $auditRequest, $status, null);
                return $res->json() ?? [];
            }
            throw $this->mapError($status, $res->json() ?? []);
        } catch (NameComApiException $e) {
            $this->audit($auditAction, $target, $auditRequest, $e->httpStatus ?: $status, $e->getMessage());
            throw $e;
        }
    }

    private function mapError(int $status, array $json): NameComApiException
    {
        $details = trim((string) ($json['details'] ?? ''));
        $remote = trim((string) ($json['message'] ?? ''));

        $msg = match (true) {
            $status === 401 => 'Name.com rejected the username or API token. Check them (use the API token, not your password) and try again.',
            $status === 403 && (stripos($details, 'two-step') !== false || stripos($details, 'two-factor') !== false)
                            => 'Name.com refused access because two-step verification is enabled on the account. Turn 2FA off for the account that owns the API token (Name.com API accounts cannot use 2FA).',
            $status === 403 => 'Name.com denied permission for this request' . ($details ? ": $details" : '.') . ' Check the API token, and that this server IP is allowed if you set an IP restriction.',
            $status === 404 => 'Domain not found in this Name.com account.',
            $status === 429 => 'Name.com rate limit reached. Wait a minute and try again.',
            $status >= 500  => 'Name.com is having problems (HTTP ' . $status . '). Try again later.',
            default         => 'Name.com error: ' . mb_substr($details ?: $remote ?: "HTTP $status", 0, 200),
        };

        return new NameComApiException($msg, $status);
    }

    private function audit(?string $action, ?string $target, array $request, ?int $status, ?string $error): void
    {
        if ($action === null) return; // reads are not audited

        try {
            NameComAuditLog::create([
                'tenant_id'          => $this->account->tenant_id,
                'user_id'            => auth()->id(),
                'namecom_account_id' => $this->account->id,
                'action'             => $action,
                'target'             => $target,
                'request'            => $request ?: null,
                'response_status'    => $status,
                'error'              => $error ? mb_substr($error, 0, 250) : null,
            ]);
        } catch (\Throwable $e) {
            \Log::warning('Name.com audit write failed', ['error' => $e->getMessage()]);
        }
    }
}
