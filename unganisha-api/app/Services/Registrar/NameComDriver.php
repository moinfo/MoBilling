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
 *   GET  /core/v1/tldpricing         (TLD catalog + USD prices, read-only)
 *   POST /core/v1/domains:checkAvailability (read-only lookup despite the verb)
 *   POST /core/v1/domains/{name}:setNameservers
 *   POST /core/v1/domains            (CREATE = real purchase; only via createDomain(),
 *                                     which requires the NameComRegistrationService)
 *   POST /core/v1/domains/{name}:lock | :unlock   (transfer lock; empty {} body)
 *   GET  /core/v1/domains/{name}:getAuthCode      (transfer-out EPP code; NEVER stored/logged/audited)
 *
 * "Domain Manager" additions (client self-service; each path verified against the official OpenAPI):
 *   GET|POST   /core/v1/domains/{name}/records            DNS records list / create
 *   PUT|DELETE /core/v1/domains/{name}/records/{id}       DNS record update / delete (records only, never domains)
 *   GET|POST   /core/v1/domains/{name}/email/forwarding   email forwarding list / create
 *   PUT|DELETE /core/v1/domains/{name}/email/forwarding/{box}
 *   GET        /core/v1/urlforwarding/{name}              URL forwarding list (by-id API, the non-deprecated one)
 *   POST       /core/v1/domains/{name}/url/forwarding     URL forwarding create (only create path)
 *   PATCH|DELETE /core/v1/urlforwarding/{name}/{id}       URL forwarding update / delete
 *   GET|POST   /core/v1/domains/{name}/vanity_nameservers glue hosts list / create
 *   PUT        /core/v1/domains/{name}/vanity_nameservers/{host}  glue host IPs (no delete)
 *   POST       /core/v1/domains/{name}:setContacts        WHOIS contacts (all four roles at once)
 * Everything else (renew, transfer, domain delete, purchase, privacy...)
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
    private const PRICING_PER_PAGE = 500;

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

    /**
     * Whole TLD catalog with account-level USD prices for a 1-year term
     * (GET /core/v1/tldpricing, paginated + paced; 429 backoff in request()).
     * @return array[] entries: tld, registrationPrice, renewalPrice, transferInPrice (null = unsupported)
     */
    public function tldPricing(int $duration = 1): array
    {
        $all = [];
        $page = 1;
        do {
            if (self::$paginatedGapMs > 0) {
                $wait = self::$lastPaginatedAt + self::$paginatedGapMs / 1000 - microtime(true);
                if ($wait > 0) usleep((int) ($wait * 1e6));
            }
            $json = $this->request('GET', '/core/v1/tldpricing', ['perPage' => self::PRICING_PER_PAGE, 'page' => $page, 'duration' => $duration]);
            self::$lastPaginatedAt = microtime(true);
            $all = array_merge($all, $json['pricing'] ?? []);
            $next = (int) ($json['nextPage'] ?? 0);
            $page = $next > $page ? $next : 0;
        } while ($page > 0 && $page <= self::MAX_PAGES);

        return $all;
    }

    /** Live account-level USD price of one TLD for $years (single read). null when unsupported. */
    public function tldPriceFor(string $tld, int $years): ?array
    {
        $json = $this->request('GET', '/core/v1/tldpricing', ['tlds' => strtolower($tld), 'duration' => $years, 'perPage' => 25, 'page' => 1]);
        foreach ($json['pricing'] ?? [] as $e) {
            if (strtolower((string) ($e['tld'] ?? '')) === strtolower($tld)) return $e;
        }
        return null;
    }

    /**
     * Read-only availability lookup (POST :checkAvailability, purchaseType=registration).
     * @return array{available: bool, reason: ?string, premium: bool, price: ?float, purchase_type: ?string}
     */
    public function checkAvailability(string $domain): array
    {
        $domain = self::validateDomainName($domain);
        return $this->checkAvailabilityMany([$domain])[$domain];
    }

    /**
     * ONE read-only :checkAvailability call for several names (max 50).
     * @param string[] $domains
     * @return array<string, array{available: bool, reason: ?string, premium: bool, price: ?float, purchase_type: ?string}> keyed by name
     */
    public function checkAvailabilityMany(array $domains): array
    {
        $names = [];
        foreach ($domains as $d) $names[] = self::validateDomainName($d);
        $names = array_values(array_unique($names));
        if (!$names || count($names) > 50) throw new \InvalidArgumentException('Provide between 1 and 50 domain names.');

        $json = $this->request('POST', '/core/v1/domains:checkAvailability', [], ['domainNames' => $names, 'purchaseType' => 'registration']);
        $by = [];
        foreach ($json['results'] ?? [] as $r) $by[strtolower((string) ($r['domainName'] ?? ''))] = $r;

        $out = [];
        foreach ($names as $domain) {
            $r = $by[$domain] ?? null;
            if (!$r) {
                $out[$domain] = ['available' => false, 'reason' => 'No result returned for this name.', 'premium' => false, 'price' => null, 'purchase_type' => null];
                continue;
            }
            $premium = (bool) ($r['premium'] ?? false);
            $type = $r['purchaseType'] ?? null;
            $purchasable = (bool) ($r['purchasable'] ?? false);
            $standard = $purchasable && !$premium && ($type === null || $type === 'registration');
            $out[$domain] = [
                'available'     => $standard,
                'reason'        => $standard ? null : ($premium && $purchasable ? 'Premium domain - not offered.' : ($r['reason'] ?? 'Not available')),
                'premium'       => $premium,
                'price'         => isset($r['purchasePrice']) ? (float) $r['purchasePrice'] : null,
                'purchase_type' => $type,
            ];
        }
        return $out;
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

    /**
     * THE ONE PURCHASE CALL (real money). Only NameComRegistrationService may pass itself in,
     * so nothing else can reach it. Standard (non-premium) registrations only: purchasePrice omitted.
     * @param array $contacts ContactsRequest shape (registrant/admin/tech/billing)
     * @param array $audit    extra audit fields (mode, domain_id, usd, by user...)
     */
    public function createDomain(NameComRegistrationService $authorizedBy, string $domain, int $years, array $contacts, array $audit = []): array
    {
        $domain = self::validateDomainName($domain);
        if ($years < 1 || $years > 10) throw new \InvalidArgumentException('Years must be between 1 and 10.');

        return $this->request(
            'POST', '/core/v1/domains', [],
            ['domain' => ['domainName' => $domain, 'contacts' => $contacts], 'years' => $years, 'purchaseType' => 'registration'],
            'domain.register', $domain, ['years' => $years] + $audit,
            true,
        );
    }

    // ── transfer-out readiness ──

    /** Registrar lock: POST :lock. @return array the Domain object */
    public function lockDomain(string $domain, array $actor = []): array
    {
        $domain = self::validateDomainName($domain);
        return $this->request('POST', "/core/v1/domains/{$domain}:lock", [], [], 'domain.lock', $domain, $actor);
    }

    /** Registrar unlock: POST :unlock. @return array the Domain object */
    public function unlockDomain(string $domain, array $actor = []): array
    {
        $domain = self::validateDomainName($domain);
        return $this->request('POST', "/core/v1/domains/{$domain}:unlock", [], [], 'domain.unlock', $domain, $actor);
    }

    /**
     * Transfer authorization (EPP) code. The audit row records ONLY that a code was requested
     * (never the value); the caller must show it once and drop it.
     */
    public function getAuthCode(string $domain, array $actor = []): string
    {
        $domain = self::validateDomainName($domain);
        $json = $this->request('GET', "/core/v1/domains/{$domain}:getAuthCode", [], [], 'domain.authcode_requested', $domain, $actor);
        $code = (string) ($json['authCode'] ?? '');
        if ($code === '') {
            throw new NameComApiException('No transfer authorization code is available for this domain right now.');
        }
        return $code;
    }

    // ── Domain Manager: DNS records / forwarding / glue hosts / contacts ──

    /** Every page of a paginated list endpoint, paced. @return array[] */
    private function pagedList(string $path, string $key): array
    {
        $all = [];
        $page = 1;
        do {
            if (self::$paginatedGapMs > 0) {
                $wait = self::$lastPaginatedAt + self::$paginatedGapMs / 1000 - microtime(true);
                if ($wait > 0) usleep((int) ($wait * 1e6));
            }
            $json = $this->request('GET', $path, ['perPage' => self::PER_PAGE, 'page' => $page]);
            self::$lastPaginatedAt = microtime(true);
            $all = array_merge($all, $json[$key] ?? []);
            $next = (int) ($json['nextPage'] ?? 0);
            $page = $next > $page ? $next : 0;
        } while ($page > 0 && $page <= self::MAX_PAGES);
        return $all;
    }

    private static function intId($id): string
    {
        $id = (string) $id;
        if (!ctype_digit($id)) throw new \InvalidArgumentException('Invalid id.');
        return $id;
    }

    private static function box(string $box): string
    {
        $b = strtolower(trim($box));
        if (!preg_match('/^[a-z0-9][a-z0-9._+-]{0,63}$/', $b)) throw new \InvalidArgumentException('Invalid mailbox name.');
        return $b;
    }

    private static function label(string $l): string
    {
        $l = strtolower(trim($l));
        if (!preg_match('/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/', $l)) throw new \InvalidArgumentException('Invalid host name.');
        return $l;
    }

    public function listRecords(string $domain): array
    {
        return $this->pagedList('/core/v1/domains/' . self::validateDomainName($domain) . '/records', 'records');
    }

    /** @param array $rec host/type/answer/ttl[/priority] */
    public function createRecord(string $domain, array $rec, array $actor = []): array
    {
        $d = self::validateDomainName($domain);
        return $this->request('POST', "/core/v1/domains/{$d}/records", [], $rec, 'dns.record_add', $d, ['type' => $rec['type'] ?? null, 'host' => $rec['host'] ?? null] + $actor);
    }

    public function updateRecord(string $domain, $id, array $rec, array $actor = []): array
    {
        $d = self::validateDomainName($domain); $id = self::intId($id);
        return $this->request('PUT', "/core/v1/domains/{$d}/records/{$id}", [], $rec, 'dns.record_edit', $d, ['id' => (int) $id, 'type' => $rec['type'] ?? null, 'host' => $rec['host'] ?? null] + $actor);
    }

    /** Deletes ONE DNS record (never a domain). */
    public function deleteRecord(string $domain, $id, array $actor = []): array
    {
        $d = self::validateDomainName($domain); $id = self::intId($id);
        return $this->request('DELETE', "/core/v1/domains/{$d}/records/{$id}", [], [], 'dns.record_delete', $d, ['id' => (int) $id] + $actor);
    }

    public function listEmailForwards(string $domain): array
    {
        return $this->pagedList('/core/v1/domains/' . self::validateDomainName($domain) . '/email/forwarding', 'emailForwarding');
    }

    public function createEmailForward(string $domain, string $box, string $to, array $actor = []): array
    {
        $d = self::validateDomainName($domain); $b = self::box($box);
        return $this->request('POST', "/core/v1/domains/{$d}/email/forwarding", [], ['emailBox' => $b, 'emailTo' => $to], 'email_forward.add', $d, ['box' => $b] + $actor);
    }

    public function updateEmailForward(string $domain, string $box, string $to, array $actor = []): array
    {
        $d = self::validateDomainName($domain); $b = self::box($box);
        return $this->request('PUT', "/core/v1/domains/{$d}/email/forwarding/{$b}", [], ['emailTo' => $to], 'email_forward.edit', $d, ['box' => $b] + $actor);
    }

    public function deleteEmailForward(string $domain, string $box, array $actor = []): array
    {
        $d = self::validateDomainName($domain); $b = self::box($box);
        return $this->request('DELETE', "/core/v1/domains/{$d}/email/forwarding/{$b}", [], [], 'email_forward.delete', $d, ['box' => $b] + $actor);
    }

    public function listUrlForwards(string $domain): array
    {
        return $this->pagedList('/core/v1/urlforwarding/' . self::validateDomainName($domain), 'urlForwarding');
    }

    /** @param array $fwd host/forwardsTo/type[/title] */
    public function createUrlForward(string $domain, array $fwd, array $actor = []): array
    {
        $d = self::validateDomainName($domain);
        return $this->request('POST', "/core/v1/domains/{$d}/url/forwarding", [], $fwd, 'url_forward.add', $d, ['host' => $fwd['host'] ?? null, 'type' => $fwd['type'] ?? null] + $actor);
    }

    public function updateUrlForward(string $domain, $id, array $fwd, array $actor = []): array
    {
        $d = self::validateDomainName($domain); $id = self::intId($id);
        return $this->request('PATCH', "/core/v1/urlforwarding/{$d}/{$id}", [], $fwd, 'url_forward.edit', $d, ['id' => (int) $id] + $actor);
    }

    public function deleteUrlForward(string $domain, $id, array $actor = []): array
    {
        $d = self::validateDomainName($domain); $id = self::intId($id);
        return $this->request('DELETE', "/core/v1/urlforwarding/{$d}/{$id}", [], [], 'url_forward.delete', $d, ['id' => (int) $id] + $actor);
    }

    public function listHosts(string $domain): array
    {
        return $this->pagedList('/core/v1/domains/' . self::validateDomainName($domain) . '/vanity_nameservers', 'vanityNameservers');
    }

    /** @param string $label subdomain part only ("ns1" for ns1.example.com) */
    public function createHost(string $domain, string $label, array $ips, array $actor = []): array
    {
        $d = self::validateDomainName($domain); $l = self::label($label);
        return $this->request('POST', "/core/v1/domains/{$d}/vanity_nameservers", [], ['hostname' => $l, 'ips' => array_values($ips)], 'host.add', $d, ['host' => "$l.$d", 'ips' => array_values($ips)] + $actor);
    }

    public function updateHost(string $domain, string $fullHostname, array $ips, array $actor = []): array
    {
        $d = self::validateDomainName($domain); $h = self::validateDomainName($fullHostname);
        return $this->request('PUT', "/core/v1/domains/{$d}/vanity_nameservers/{$h}", [], ['ips' => array_values($ips)], 'host.edit', $d, ['host' => $h, 'ips' => array_values($ips)] + $actor);
    }

    /**
     * WHOIS contacts: all four roles must be sent complete (the API replaces them at once).
     * The audit row records only WHICH roles changed, never the personal data.
     */
    public function setContacts(string $domain, array $contacts, array $changedRoles = [], array $actor = []): array
    {
        $d = self::validateDomainName($domain);
        return $this->request('POST', "/core/v1/domains/{$d}:setContacts", [], ['contacts' => $contacts], 'contacts.set', $d, ['roles' => $changedRoles] + $actor);
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
        $r = $this->checkAvailability($domain);
        return ['available' => $r['available'], 'reason' => $r['reason']];
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

    /** Allow-list: refuses anything but the permitted calls BEFORE touching the network. */
    public static function assertAllowed(string $method, string $path, bool $createAuthorized = false): void
    {
        $m = strtoupper($method);
        $dn = '[a-z0-9.-]+';
        $ok = ($m === 'GET' && preg_match('#^/core/v1/domains/[a-z0-9.-]+:getAuthCode$#', $path))
            // Domain Manager (see class docblock): DNS records, forwarding, glue hosts, contacts
            || (in_array($m, ['GET', 'POST'], true) && preg_match("#^/core/v1/domains/$dn/(records|email/forwarding|vanity_nameservers)$#", $path))
            || (in_array($m, ['PUT', 'DELETE'], true) && preg_match("#^/core/v1/domains/$dn/records/[0-9]+$#", $path))
            || (in_array($m, ['PUT', 'DELETE'], true) && preg_match("#^/core/v1/domains/$dn/email/forwarding/[a-z0-9][a-z0-9._+-]{0,63}$#", $path))
            || ($m === 'PUT' && preg_match("#^/core/v1/domains/$dn/vanity_nameservers/$dn$#", $path))
            || ($m === 'POST' && preg_match("#^/core/v1/domains/$dn/url/forwarding$#", $path))
            || ($m === 'GET' && preg_match("#^/core/v1/urlforwarding/$dn$#", $path))
            || (in_array($m, ['PATCH', 'DELETE'], true) && preg_match("#^/core/v1/urlforwarding/$dn/[0-9]+$#", $path))
            || ($m === 'POST' && preg_match("#^/core/v1/domains/$dn:setContacts$#", $path))
            || ($m === 'POST' && preg_match('#^/core/v1/domains/[a-z0-9.-]+:(lock|unlock)$#', $path))
            || ($m === 'GET' && ($path === '/core/v1/domains' || $path === '/core/v1/tldpricing' || preg_match('#^/core/v1/domains/[a-z0-9.-]+$#', $path)))
            || ($m === 'POST' && ($path === '/core/v1/domains:checkAvailability' || preg_match('#^/core/v1/domains/[a-z0-9.-]+:setNameservers$#', $path)))
            || ($m === 'POST' && $path === '/core/v1/domains' && $createAuthorized);
        if (!$ok) {
            throw new NameComApiException('This request is not permitted: Name.com access is limited to reading, availability checks, nameservers, the transfer lock / authorization code, DNS records, forwarding, glue hosts, contacts and (staff-approved) registration.');
        }
    }

    private function request(string $method, string $path, array $query = [], array $body = [], ?string $auditAction = null, ?string $target = null, array $auditRequest = [], bool $createAuthorized = false): array
    {
        self::assertAllowed($method, $path, $createAuthorized);
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
                    $res = match ($method) {
                        'GET'    => $http->get($url, $query),
                        'DELETE' => $http->delete($url),
                        'PUT'    => $http->put($url, $body),
                        'PATCH'  => $http->patch($url, $body),
                        default  => $body === [] ? $http->withBody('{}', 'application/json')->post($url) : $http->post($url, $body), // lock/unlock need a literal {}
                    };
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
