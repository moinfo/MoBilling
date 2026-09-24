<?php

namespace App\Services\Registrar;

use App\Exceptions\NameComApiException;
use App\Exceptions\RegistrarApiException;
use App\Models\Domain;
use App\Models\DomainLog;
use App\Models\User;
use App\Notifications\DomainManagerActivityNotification;
use Illuminate\Support\Facades\Notification;

/**
 * "Domain Manager": client self-service over a linked domain's registrar-side DNS records,
 * URL / email forwarding, glue (vanity) hosts and WHOIS contacts.
 *
 * Everything here returns NEUTRAL data (no supplier names, ids of accounts, USD...) because the
 * portal controller hands it straight to clients. Validation is static and makes no network call.
 * DomainLog actions are all prefixed `dm_` and have neutral labels (see activityLabel()).
 */
class NameComManagerService
{
    public const MAX_RECORDS = 100;
    public const MAX_FORWARDS = 20;
    public const MAX_HOSTS = 10;
    public const MAX_HOST_IPS = 4;
    public const MIN_TTL = 300;
    public const MAX_TTL = 86400;
    public const TTLS = [300, 600, 1800, 3600, 7200, 14400, 28800, 43200, 86400];
    public const RECORD_TYPES = ['A', 'AAAA', 'ANAME', 'CNAME', 'MX', 'TXT', 'SRV'];
    public const FORWARD_TYPES = ['permanent' => 'redirect', 'temporary' => '302', 'masked' => 'masked'];
    public const ROLES = ['registrant', 'admin', 'tech', 'billing'];
    /** Fallback only when the zone itself does not reveal the domain's own DNS servers. */
    public const DEFAULT_DNS_SERVERS = ['ns1.name.com', 'ns2.name.com', 'ns3.name.com', 'ns4.name.com'];

    /** action => [max successes, window in hours] (per domain; counted from DomainLog) */
    private const LIMITS = [
        'dns'      => [['dm_dns_record_added', 'dm_dns_record_edited', 'dm_dns_record_deleted'], 40, 1],
        'forward'  => [['dm_url_forward_added', 'dm_url_forward_edited', 'dm_url_forward_removed', 'dm_email_forward_added', 'dm_email_forward_edited', 'dm_email_forward_removed'], 30, 1],
        'host'     => [['dm_host_added', 'dm_host_edited'], 10, 24],
        'contacts' => [['dm_contacts_changed'], 3, 24],
    ];

    private const LABELS = [
        'dm_dns_record_added' => 'DNS record added', 'dm_dns_record_edited' => 'DNS record changed', 'dm_dns_record_deleted' => 'DNS record removed',
        'dm_url_forward_added' => 'Website forwarding added', 'dm_url_forward_edited' => 'Website forwarding changed', 'dm_url_forward_removed' => 'Website forwarding removed',
        'dm_email_forward_added' => 'Email forwarding added', 'dm_email_forward_edited' => 'Email forwarding changed', 'dm_email_forward_removed' => 'Email forwarding removed',
        'dm_host_added' => 'Custom nameserver host added', 'dm_host_edited' => 'Custom nameserver host changed',
        'dm_contacts_changed' => 'Contact details changed', 'dm_dns_servers_switched' => 'Nameservers changed',
    ];

    public function __construct(private DomainRegistrarManager $registrar, private NameComDomainService $domains) {}

    public static function activityLabel(string $action): string
    {
        return self::LABELS[$action] ?? 'Domain updated';
    }

    private function driver(Domain $d): NameComDriver
    {
        return $this->registrar->namecomForDomain($d);
    }

    // ═════════════ errors (client-safe) ═════════════

    /** Generic, supplier-free text for any registrar-side failure. */
    public static function clientMessage(\Throwable $e): string
    {
        $status = $e instanceof NameComApiException ? $e->httpStatus : 0;
        return match (true) {
            $status === 404 => 'That item could not be found. Refresh the page and try again.',
            $status === 400 || $status === 409 || $status === 422 => 'The change was not accepted. Please check the values and try again.',
            $status === 403 || $status === 423 => 'This domain cannot be changed right now (it may be locked or under review). Please contact us.',
            $status === 429 => 'Too many requests. Please wait a minute and try again.',
            $status >= 500 => 'The service is temporarily unavailable. Please try again later.',
            default => 'We could not complete this right now. Please try again later or contact us.',
        };
    }

    // ═════════════ logging / limits / staff alerts ═════════════

    private function limited(Domain $d, string $bucket): void
    {
        [$actions, $max, $hours] = self::LIMITS[$bucket];
        $n = DomainLog::where('domain_id', $d->id)->whereIn('action', $actions)->where('status', 'success')
            ->where('created_at', '>=', now()->subHours($hours))->count();
        if ($n >= $max) {
            throw new \DomainException('You have reached the limit of ' . $max . ' changes of this kind per ' . ($hours === 1 ? 'hour' : 'day') . ' for this domain. Please try again later.');
        }
    }

    private function log(Domain $d, string $action, array $actor, array $extra = []): void
    {
        DomainLog::create(['tenant_id' => $d->tenant_id, 'domain_id' => $d->id, 'action' => $action, 'request' => $extra + $actor, 'status' => 'success']);
    }

    private function notifyStaff(Domain $d, string $what, array $actor): void
    {
        try {
            $staff = User::withPermission($d->tenant_id, 'domains.manage_dns');
            if ($staff->isNotEmpty()) Notification::send($staff, new DomainManagerActivityNotification($d, $what, isset($actor['by_portal_user'])));
        } catch (\Throwable $e) {
            report($e);
        }
    }

    // ═════════════ DNS: mapping + validation ═════════════

    /** Registrar record -> the shape shared with the Linode UI components. */
    public static function mapRecord(array $r): array
    {
        $type = strtoupper((string) ($r['type'] ?? ''));
        $host = strtolower((string) ($r['host'] ?? ''));
        $answer = (string) ($r['answer'] ?? '');
        $out = ['id' => (int) ($r['id'] ?? 0), 'type' => $type, 'name' => $host === '@' ? '' : $host, 'target' => $answer,
            'ttl_sec' => (int) ($r['ttl'] ?? 0), 'locked' => $type === 'NS'];
        if ($type === 'MX') $out['priority'] = (int) ($r['priority'] ?? 0);
        if ($type === 'SRV') {
            $out['priority'] = (int) ($r['priority'] ?? 0);
            if (preg_match('/^(\d+)\s+(\d+)\s+(\S+)$/', $answer, $m)) { $out['weight'] = (int) $m[1]; $out['port'] = (int) $m[2]; $out['target'] = rtrim($m[3], '.'); }
            if (preg_match('/^_([^.]+)\._([^.]+)(?:\.(.+))?$/', $host, $m)) { $out['service'] = $m[1]; $out['protocol'] = $m[2]; $out['name'] = $m[3] ?? ''; }
        }
        return $out;
    }

    /**
     * Validate a shared-shape payload and return [registrar body, normalised shape].
     * @param array[] $existing current records in shared shape (duplicate / CNAME conflict checks)
     * @throws \InvalidArgumentException
     */
    public static function validateRecord(array $in, array $existing = [], ?string $ignoreId = null): array
    {
        $type = strtoupper(trim((string) ($in['type'] ?? '')));
        if ($type === 'NS') throw new \InvalidArgumentException('Nameserver (NS) records cannot be changed here.');
        if (!in_array($type, self::RECORD_TYPES, true)) throw new \InvalidArgumentException('Record type must be one of: ' . implode(', ', self::RECORD_TYPES) . '.');

        $name = strtolower(trim((string) ($in['name'] ?? '')));
        if ($name === '@') $name = '';
        if ($name !== '' && !preg_match('/^[a-z0-9_*]([a-z0-9_.*-]{0,251})$/', $name)) {
            throw new \InvalidArgumentException('Invalid record name. Use letters, digits, "-", "_", or leave empty for the root domain.');
        }
        if (in_array($type, ['CNAME'], true) && $name === '') throw new \InvalidArgumentException('A CNAME cannot be set on the root domain. Use an A record or ANAME instead.');

        $target = trim((string) ($in['target'] ?? ''));
        if ($target === '') throw new \InvalidArgumentException('Value is required.');
        $hostRe = '/^(?=.{1,253}$)([a-z0-9_]([a-z0-9_-]{0,61}[a-z0-9_])?\.)*[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/';
        switch ($type) {
            case 'A':
                if (!filter_var($target, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)) throw new \InvalidArgumentException('An A record needs an IPv4 address.');
                break;
            case 'AAAA':
                if (!filter_var($target, FILTER_VALIDATE_IP, FILTER_FLAG_IPV6)) throw new \InvalidArgumentException('An AAAA record needs an IPv6 address.');
                break;
            case 'ANAME': case 'CNAME': case 'MX': case 'SRV':
                $target = rtrim(strtolower($target), '.');
                if (!preg_match($hostRe, $target)) throw new \InvalidArgumentException("$type target must be a hostname.");
                break;
            case 'TXT':
                if (strlen($target) > 2000) throw new \InvalidArgumentException('TXT value is too long.');
                break;
        }

        $ttl = $in['ttl_sec'] ?? self::MIN_TTL;
        $ttl = ($ttl === null || $ttl === '' || (int) $ttl === 0) ? self::MIN_TTL : $ttl;
        if (!is_numeric($ttl) || (int) $ttl < self::MIN_TTL || (int) $ttl > self::MAX_TTL) {
            throw new \InvalidArgumentException('TTL must be between ' . self::MIN_TTL . ' and ' . self::MAX_TTL . ' seconds.');
        }
        $shape = ['type' => $type, 'name' => $name, 'target' => $target, 'ttl_sec' => (int) $ttl];
        $body = ['type' => $type, 'host' => $name, 'answer' => $target, 'ttl' => (int) $ttl];

        if ($type === 'MX' || $type === 'SRV') {
            $p = $in['priority'] ?? null;
            if (!is_numeric($p) || $p < 0 || $p > 65535) throw new \InvalidArgumentException('Priority (0-65535) is required for MX and SRV records.');
            $shape['priority'] = $body['priority'] = (int) $p;
        }
        if ($type === 'SRV') {
            foreach (['weight', 'port'] as $k) {
                $v = $in[$k] ?? null;
                if (!is_numeric($v) || $v < 0 || $v > 65535) throw new \InvalidArgumentException(ucfirst($k) . ' (0-65535) is required for SRV records.');
                $shape[$k] = (int) $v;
            }
            $svc = ltrim(strtolower(trim((string) ($in['service'] ?? ''))), '_');
            $proto = ltrim(strtolower(trim((string) ($in['protocol'] ?? ''))), '_');
            if (!preg_match('/^[a-z0-9-]{1,30}$/', $svc)) throw new \InvalidArgumentException('SRV records need a service, e.g. "sip".');
            if (!in_array($proto, ['tcp', 'udp', 'tls'], true)) throw new \InvalidArgumentException('SRV protocol must be tcp, udp or tls.');
            $shape += ['service' => $svc, 'protocol' => $proto];
            $body['host'] = "_{$svc}._{$proto}" . ($name !== '' ? ".$name" : '');
            $body['answer'] = "{$shape['weight']} {$shape['port']} {$target}";
        }

        foreach ($existing as $e) {
            if ($ignoreId !== null && (string) ($e['id'] ?? '') === $ignoreId) continue;
            $eType = strtoupper((string) ($e['type'] ?? ''));
            $eName = strtolower((string) ($e['name'] ?? ''));
            $same = $eType === $type && $eName === $name && strtolower(rtrim((string) ($e['target'] ?? ''), '.')) === strtolower(rtrim($target, '.'))
                && ($type !== 'MX' || (int) ($e['priority'] ?? 0) === ($shape['priority'] ?? 0));
            if ($same) throw new \InvalidArgumentException('An identical record already exists.');
            if ($eName === $name && $type !== 'SRV' && $eType !== 'SRV') {
                if ($type === 'CNAME' && $eType !== 'CNAME') throw new \InvalidArgumentException("A CNAME cannot share a name with an existing $eType record.");
                if ($eType === 'CNAME' && $type !== 'CNAME') throw new \InvalidArgumentException('That name already has a CNAME record; a CNAME cannot coexist with other records.');
            }
        }
        return [$body, $shape];
    }

    /** True when every live nameserver is one of the registrar's own DNS servers (their DNS is authoritative). */
    public static function dnsInUse(array $nameservers): bool
    {
        if (!$nameservers) return false;
        foreach ($nameservers as $ns) {
            if (!preg_match('/^ns[0-9a-z]*\.name\.com$/', rtrim(strtolower((string) $ns), '.'))) return false;
        }
        return true;
    }

    // ═════════════ DNS: operations ═════════════

    /** @return array{records: array[], in_use: bool, max_records: int, ttls: int[]} */
    public function dns(Domain $d): array
    {
        $drv = $this->driver($d);
        // The zone's own NS records are hostnames on the supplier's domain: not shown to clients (and not editable anyway).
        $rows = array_values(array_filter(array_map([self::class, 'mapRecord'], $drv->listRecords($d->name)),
            fn ($r) => !($r['type'] === 'NS' && self::dnsInUse([$r['target']]))));
        return ['records' => $rows, 'in_use' => self::dnsInUse($drv->nameservers($d->name)), 'max_records' => self::MAX_RECORDS, 'ttls' => self::TTLS];
    }

    public function addRecord(Domain $d, array $in, array $actor): array
    {
        $this->limited($d, 'dns');
        $drv = $this->driver($d);
        $existing = array_map([self::class, 'mapRecord'], $drv->listRecords($d->name));
        if (count($existing) >= self::MAX_RECORDS) throw new \DomainException('This domain has reached the limit of ' . self::MAX_RECORDS . ' DNS records.');
        [$body, $shape] = self::validateRecord($in, $existing);
        $res = $drv->createRecord($d->name, $body, $actor);
        $this->log($d, 'dm_dns_record_added', $actor, ['type' => $shape['type'], 'name' => $shape['name']]);
        return self::mapRecord($res + $body);
    }

    public function editRecord(Domain $d, string $id, array $in, array $actor): array
    {
        $this->limited($d, 'dns');
        $drv = $this->driver($d);
        $existing = array_map([self::class, 'mapRecord'], $drv->listRecords($d->name));
        $cur = collect($existing)->firstWhere('id', (int) $id);
        if (!$cur) throw new \DomainException('That record no longer exists. Refresh the page.');
        if ($cur['type'] === 'NS') throw new \InvalidArgumentException('Nameserver (NS) records cannot be changed here.');
        [$body, $shape] = self::validateRecord($in, $existing, $id);
        $res = $drv->updateRecord($d->name, $id, $body, $actor);
        $this->log($d, 'dm_dns_record_edited', $actor, ['type' => $shape['type'], 'name' => $shape['name']]);
        return self::mapRecord(['id' => (int) $id] + $res + $body);
    }

    public function deleteRecord(Domain $d, string $id, array $actor): void
    {
        $this->limited($d, 'dns');
        $drv = $this->driver($d);
        $cur = collect(array_map([self::class, 'mapRecord'], $drv->listRecords($d->name)))->firstWhere('id', (int) $id);
        if (!$cur) throw new \DomainException('That record no longer exists. Refresh the page.');
        if ($cur['type'] === 'NS') throw new \InvalidArgumentException('Nameserver (NS) records cannot be removed here.');
        $drv->deleteRecord($d->name, $id, $actor);
        $this->log($d, 'dm_dns_record_deleted', $actor, ['type' => $cur['type'], 'name' => $cur['name']]);
    }

    /** The nameservers that make the registrar-side DNS authoritative for this domain. */
    public function defaultDnsServers(Domain $d): array
    {
        $fromZone = collect($this->driver($d)->listRecords($d->name))
            ->filter(fn ($r) => strtoupper((string) ($r['type'] ?? '')) === 'NS' && in_array((string) ($r['host'] ?? ''), ['', '@'], true))
            ->map(fn ($r) => rtrim(strtolower((string) ($r['answer'] ?? '')), '.'))->filter(fn ($h) => self::dnsInUse([$h]))->unique()->values()->all();
        if (count($fromZone) >= 2) return $fromZone;
        $orig = array_values(array_filter((array) NameComDomainService::original($d), fn ($h) => self::dnsInUse([$h])));
        return count($orig) >= 2 ? $orig : self::DEFAULT_DNS_SERVERS;
    }

    /** Explicit, client-confirmed switch to our DNS servers (reuses the guarded nameserver update). */
    public function useDefaultDnsServers(Domain $d, array $actor): array
    {
        $servers = $this->defaultDnsServers($d);
        $r = $this->domains->updateNameservers($d, $servers, $actor);
        return $r;
    }

    // ═════════════ contacts ═════════════

    private const CONTACT_FIELDS = ['firstName' => 'first_name', 'lastName' => 'last_name', 'companyName' => 'company', 'address1' => 'address1', 'address2' => 'address2',
        'city' => 'city', 'state' => 'state', 'zip' => 'zip', 'country' => 'country', 'email' => 'email', 'phone' => 'phone', 'fax' => 'fax'];

    private static function mapContact(?array $c): array
    {
        $o = [];
        foreach (self::CONTACT_FIELDS as $api => $ours) $o[$ours] = (string) ($c[$api] ?? '');
        $o['verified'] = isset($c['isVerified']) ? (bool) $c['isVerified'] : null;
        return $o;
    }

    /** @return array{contacts: array, transfer_lock_until: ?string} */
    public function contacts(Domain $d): array
    {
        $info = $this->driver($d)->getDomain($d->name);
        $out = [];
        foreach (self::ROLES as $role) $out[$role] = self::mapContact($info['contacts'][$role] ?? null);
        return ['contacts' => $out, 'transfer_lock_until' => !empty($info['transferLockExpiresAt']) ? substr((string) $info['transferLockExpiresAt'], 0, 10) : null];
    }

    /** @return array our-shaped, validated single contact @throws \InvalidArgumentException */
    public static function validateContact(string $role, array $c): array
    {
        $r = ucfirst($role);
        $clean = [];
        foreach (self::CONTACT_FIELDS as $ours) $clean[$ours] = trim((string) ($c[$ours] ?? ''));
        foreach (['first_name', 'last_name', 'address1', 'city', 'state', 'zip', 'country', 'email', 'phone'] as $req) {
            if ($clean[$req] === '') throw new \InvalidArgumentException("$r contact: " . str_replace('_', ' ', $req) . ' is required.');
        }
        foreach ($clean as $k => $v) {
            if (mb_strlen($v) > 200) throw new \InvalidArgumentException("$r contact: " . str_replace('_', ' ', $k) . ' is too long.');
        }
        $clean['country'] = strtoupper($clean['country']);
        if (!preg_match('/^[A-Z]{2}$/', $clean['country'])) throw new \InvalidArgumentException("$r contact: country must be a 2-letter code such as TZ.");
        if (!filter_var($clean['email'], FILTER_VALIDATE_EMAIL)) throw new \InvalidArgumentException("$r contact: email address is not valid.");
        if (!preg_match('/^\+[1-9]\d{7,14}$/', $clean['phone'])) throw new \InvalidArgumentException("$r contact: phone must be in international format, e.g. +255712345678.");
        if ($clean['fax'] !== '' && !preg_match('/^\+[1-9]\d{7,14}$/', $clean['fax'])) throw new \InvalidArgumentException("$r contact: fax must be in international format.");
        return $clean;
    }

    private static function toApiContact(array $ours): array
    {
        $o = [];
        foreach (self::CONTACT_FIELDS as $api => $k) {
            $v = (string) ($ours[$k] ?? '');
            if ($v !== '' || in_array($api, ['companyName', 'address2', 'fax'], true) === false) $o[$api] = $v;
        }
        return $o;
    }

    /**
     * @param array<string,array> $edited role => our-shaped contact (only the roles being changed)
     * @return array{changed: string[]}
     */
    public function saveContacts(Domain $d, array $edited, array $actor): array
    {
        $this->limited($d, 'contacts');
        $clean = [];
        foreach ($edited as $role => $c) {
            if (!in_array($role, self::ROLES, true)) throw new \InvalidArgumentException('Unknown contact type.');
            $clean[$role] = self::validateContact($role, (array) $c);
        }
        if (!$clean) throw new \InvalidArgumentException('Nothing to save.');

        $drv = $this->driver($d);
        $info = $drv->getDomain($d->name);
        $send = []; $changed = [];
        foreach (self::ROLES as $role) {
            $current = self::mapContact($info['contacts'][$role] ?? null);
            $merged = $clean[$role] ?? $current;
            $cmp = fn ($x) => array_diff_key($x, ['verified' => 1]);
            if (isset($clean[$role]) && $cmp($current) != $cmp($merged)) $changed[] = $role;
            $send[$role] = self::toApiContact($merged);
        }
        if (!$changed) return ['changed' => []];

        // The API replaces all four roles at once, so every role must be complete.
        foreach (self::ROLES as $role) {
            foreach (['firstName', 'lastName', 'address1', 'city', 'state', 'zip', 'country', 'email', 'phone'] as $req) {
                if (($send[$role][$req] ?? '') === '') throw new \InvalidArgumentException(ucfirst($role) . ' contact is incomplete - please fill in all its required fields too.');
            }
        }
        $drv->setContacts($d->name, $send, $changed, $actor);
        $this->log($d, 'dm_contacts_changed', $actor, ['roles' => $changed]);
        $this->notifyStaff($d, 'contacts', $actor);
        return ['changed' => $changed];
    }

    // ═════════════ forwarding ═════════════

    /** Refuses non-public / loopback / internal targets. @throws \InvalidArgumentException */
    public static function validateForwardTarget(string $url, string $ownDomain): string
    {
        $url = trim($url);
        if (mb_strlen($url) > 2000 || preg_match('/[\s<>"\'`\\\\]/', $url)) throw new \InvalidArgumentException('The destination address is not a valid web address.');
        $p = parse_url($url);
        if (!$p || !in_array(strtolower($p['scheme'] ?? ''), ['http', 'https'], true) || empty($p['host'])) {
            throw new \InvalidArgumentException('The destination must be a web address starting with http:// or https://.');
        }
        if (isset($p['user']) || isset($p['pass'])) throw new \InvalidArgumentException('The destination cannot contain a username or password.');
        $host = strtolower(trim($p['host'], '[]'));
        $host = rtrim($host, '.');
        if (isset($p['port']) && !in_array((int) $p['port'], [80, 443, 8080, 8443], true)) throw new \InvalidArgumentException('The destination port is not allowed.');
        self::assertPublicHost($host, 'destination');
        if ($host === strtolower($ownDomain) || str_ends_with($host, '.' . strtolower($ownDomain))) {
            // forwarding to itself would loop unless it points at another sub-host; keep it simple and safe
            throw new \InvalidArgumentException('The destination cannot be on this same domain.');
        }
        return $url;
    }

    /** IPs must be public; names must look like public internet hosts. @throws \InvalidArgumentException */
    private static function assertPublicHost(string $host, string $what): void
    {
        if (filter_var($host, FILTER_VALIDATE_IP)) {
            if (!filter_var($host, FILTER_VALIDATE_IP, FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE)) {
                throw new \InvalidArgumentException("The $what cannot be a private or internal address.");
            }
            return;
        }
        if (preg_match('/^\d+$|^0x[0-9a-f]+$/i', $host) || preg_match('/^[\d.]+$/', $host)) throw new \InvalidArgumentException("The $what is not a valid address.");
        if (!str_contains($host, '.') || preg_match('/(^|\.)(localhost|local|localdomain|internal|intranet|lan|home|corp|test|invalid|example)$/', $host)) {
            throw new \InvalidArgumentException("The $what cannot be a local or internal address.");
        }
        if (!preg_match('/^(?=.{4,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/', $host)) {
            throw new \InvalidArgumentException("The $what is not a valid address.");
        }
    }

    public static function normalizeUrlForward(array $in, string $ownDomain, bool $partial = false): array
    {
        $out = [];
        if (!$partial || array_key_exists('host', $in)) {
            $h = strtolower(trim((string) ($in['host'] ?? '')));
            if ($h === '@') $h = '';
            if ($h !== '' && !preg_match('/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?){0,3}$/', $h)) {
                throw new \InvalidArgumentException('Invalid subdomain. Use e.g. "www", or leave empty for the main domain.');
            }
            $out['host'] = $h;
        }
        if (!$partial || array_key_exists('target', $in)) {
            $out['forwardsTo'] = self::validateForwardTarget((string) ($in['target'] ?? ''), $ownDomain);
        }
        if (!$partial || array_key_exists('type', $in)) {
            $t = (string) ($in['type'] ?? 'permanent');
            if (!isset(self::FORWARD_TYPES[$t])) throw new \InvalidArgumentException('Forwarding type must be permanent, temporary or masked.');
            $out['type'] = self::FORWARD_TYPES[$t];
        }
        if (array_key_exists('title', $in)) {
            $title = trim(strip_tags((string) $in['title']));
            if (mb_strlen($title) > 100) throw new \InvalidArgumentException('The page title is too long (max 100 characters).');
            $out['title'] = $title;
        }
        return $out;
    }

    private static function mapUrlForward(array $f): array
    {
        $back = array_flip(self::FORWARD_TYPES);
        return ['id' => (int) ($f['id'] ?? 0), 'host' => (string) ($f['host'] ?? ''), 'target' => (string) ($f['forwardsTo'] ?? ''),
            'type' => $back[$f['type'] ?? 'redirect'] ?? 'permanent', 'title' => $f['title'] ?? null];
    }

    /** @return array[] */
    public function urlForwards(Domain $d): array
    {
        return array_map([self::class, 'mapUrlForward'], $this->driver($d)->listUrlForwards($d->name));
    }

    public function addUrlForward(Domain $d, array $in, array $actor): array
    {
        $this->limited($d, 'forward');
        $body = self::normalizeUrlForward($in, $d->name);
        $drv = $this->driver($d);
        $list = $drv->listUrlForwards($d->name);
        if (count($list) >= self::MAX_FORWARDS) throw new \DomainException('This domain has reached the limit of ' . self::MAX_FORWARDS . ' website forwards.');
        foreach ($list as $f) if (strtolower((string) ($f['host'] ?? '')) === $body['host']) throw new \InvalidArgumentException('That address already has a forward. Edit it instead.');
        $res = $drv->createUrlForward($d->name, $body, $actor);
        $this->log($d, 'dm_url_forward_added', $actor, ['host' => $body['host']]);
        $this->notifyStaff($d, 'url_forward', $actor);
        return self::mapUrlForward($res + ['host' => $body['host'], 'forwardsTo' => $body['forwardsTo'], 'type' => $body['type']]);
    }

    public function editUrlForward(Domain $d, string $id, array $in, array $actor): array
    {
        $this->limited($d, 'forward');
        $drv = $this->driver($d);
        $list = $drv->listUrlForwards($d->name);
        $cur = collect($list)->firstWhere('id', (int) $id);
        if (!$cur) throw new \DomainException('That forward no longer exists. Refresh the page.');
        $body = self::normalizeUrlForward($in, $d->name, true);
        if (!$body) throw new \InvalidArgumentException('Nothing to change.');
        if (isset($body['host'])) foreach ($list as $f) if ((int) $f['id'] !== (int) $id && strtolower((string) ($f['host'] ?? '')) === $body['host']) throw new \InvalidArgumentException('That address already has a forward.');
        $res = $drv->updateUrlForward($d->name, $id, $body, $actor);
        $this->log($d, 'dm_url_forward_edited', $actor, ['host' => $body['host'] ?? ($cur['host'] ?? '')]);
        $this->notifyStaff($d, 'url_forward', $actor);
        return self::mapUrlForward($res + $body + $cur);
    }

    public function deleteUrlForward(Domain $d, string $id, array $actor): void
    {
        $this->limited($d, 'forward');
        $drv = $this->driver($d);
        $cur = collect($drv->listUrlForwards($d->name))->firstWhere('id', (int) $id);
        if (!$cur) throw new \DomainException('That forward no longer exists. Refresh the page.');
        $drv->deleteUrlForward($d->name, $id, $actor);
        $this->log($d, 'dm_url_forward_removed', $actor, ['host' => $cur['host'] ?? '']);
    }

    public static function validateEmailForward(array $in, string $ownDomain, bool $needBox = true): array
    {
        $out = [];
        if ($needBox) {
            $box = strtolower(trim((string) ($in['box'] ?? '')));
            if (str_contains($box, '@')) $box = explode('@', $box)[0];
            if (str_contains($box, '*')) throw new \InvalidArgumentException('Catch-all forwarding (*) is not supported.');
            if (!preg_match('/^[a-z0-9][a-z0-9._+-]{0,63}$/', $box)) throw new \InvalidArgumentException('Invalid mailbox name. Use letters, digits and . _ + - only.');
            $out['box'] = $box;
        }
        $to = strtolower(trim((string) ($in['to'] ?? '')));
        if (mb_strlen($to) > 254 || !filter_var($to, FILTER_VALIDATE_EMAIL) || preg_match('/[\s,;<>"]/', $to)) throw new \InvalidArgumentException('Enter one valid destination email address.');
        $toDomain = substr(strrchr($to, '@'), 1);
        if ($toDomain === strtolower($ownDomain) || str_ends_with($toDomain, '.' . strtolower($ownDomain))) throw new \InvalidArgumentException('The destination cannot be an address on this same domain.');
        self::assertPublicHost($toDomain, 'destination');
        $out['to'] = $to;
        return $out;
    }

    /** @return array[] */
    public function emailForwards(Domain $d): array
    {
        return array_map(fn ($f) => ['box' => (string) ($f['emailBox'] ?? ''), 'address' => ($f['emailBox'] ?? '') . '@' . $d->name, 'to' => (string) ($f['emailTo'] ?? '')],
            $this->driver($d)->listEmailForwards($d->name));
    }

    public function addEmailForward(Domain $d, array $in, array $actor): array
    {
        $this->limited($d, 'forward');
        $v = self::validateEmailForward($in, $d->name);
        $drv = $this->driver($d);
        $list = $drv->listEmailForwards($d->name);
        if (count($list) >= self::MAX_FORWARDS) throw new \DomainException('This domain has reached the limit of ' . self::MAX_FORWARDS . ' email forwards.');
        foreach ($list as $f) if (strtolower((string) ($f['emailBox'] ?? '')) === $v['box']) throw new \InvalidArgumentException('That address already has a forward. Edit it instead.');
        $drv->createEmailForward($d->name, $v['box'], $v['to'], $actor);
        $this->log($d, 'dm_email_forward_added', $actor, ['box' => $v['box']]);
        $this->notifyStaff($d, 'email_forward', $actor);
        return ['box' => $v['box'], 'address' => $v['box'] . '@' . $d->name, 'to' => $v['to']];
    }

    public function editEmailForward(Domain $d, string $box, array $in, array $actor): array
    {
        $this->limited($d, 'forward');
        $box = strtolower($box);
        $v = self::validateEmailForward($in, $d->name, false);
        $drv = $this->driver($d);
        if (!collect($drv->listEmailForwards($d->name))->contains(fn ($f) => strtolower((string) ($f['emailBox'] ?? '')) === $box)) {
            throw new \DomainException('That forward no longer exists. Refresh the page.');
        }
        $drv->updateEmailForward($d->name, $box, $v['to'], $actor);
        $this->log($d, 'dm_email_forward_edited', $actor, ['box' => $box]);
        $this->notifyStaff($d, 'email_forward', $actor);
        return ['box' => $box, 'address' => $box . '@' . $d->name, 'to' => $v['to']];
    }

    public function deleteEmailForward(Domain $d, string $box, array $actor): void
    {
        $this->limited($d, 'forward');
        $box = strtolower($box);
        $drv = $this->driver($d);
        if (!collect($drv->listEmailForwards($d->name))->contains(fn ($f) => strtolower((string) ($f['emailBox'] ?? '')) === $box)) {
            throw new \DomainException('That forward no longer exists. Refresh the page.');
        }
        $drv->deleteEmailForward($d->name, $box, $actor);
        $this->log($d, 'dm_email_forward_removed', $actor, ['box' => $box]);
    }

    // ═════════════ custom nameserver hosts (glue) ═════════════

    /** @return array{label: string, ips: string[]} @throws \InvalidArgumentException */
    public static function validateHost(string $hostInput, array $ips, string $ownDomain, bool $needHost = true): array
    {
        $out = ['label' => ''];
        if ($needHost) {
            $h = rtrim(strtolower(trim($hostInput)), '.');
            $own = strtolower($ownDomain);
            if (str_ends_with($h, '.' . $own)) $h = substr($h, 0, -strlen($own) - 1);
            elseif ($h === $own || str_contains($h, '.')) throw new \InvalidArgumentException("The host name must be a name under $own, like ns1.$own.");
            if (!preg_match('/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/', $h)) throw new \InvalidArgumentException('Invalid host name. Use letters, digits and "-" (for example "ns1").');
            $out['label'] = $h;
        }
        $clean = [];
        foreach ($ips as $ip) {
            $ip = trim((string) $ip);
            if ($ip === '') continue;
            if (!filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE)) {
                throw new \InvalidArgumentException("\"$ip\" is not a public IP address. Private and reserved addresses are not allowed.");
            }
            $clean[] = strtolower($ip);
        }
        $clean = array_values(array_unique($clean));
        if (!$clean) throw new \InvalidArgumentException('Provide at least one IP address.');
        if (count($clean) > self::MAX_HOST_IPS) throw new \InvalidArgumentException('At most ' . self::MAX_HOST_IPS . ' IP addresses per host.');
        $out['ips'] = $clean;
        return $out;
    }

    /** @return array[] */
    public function hosts(Domain $d): array
    {
        return array_map(fn ($h) => ['hostname' => (string) ($h['hostname'] ?? ''), 'ips' => array_values((array) ($h['ips'] ?? []))], $this->driver($d)->listHosts($d->name));
    }

    public function addHost(Domain $d, string $host, array $ips, array $actor): array
    {
        $this->limited($d, 'host');
        $v = self::validateHost($host, $ips, $d->name);
        $drv = $this->driver($d);
        if (count($drv->listHosts($d->name)) >= self::MAX_HOSTS) throw new \DomainException('This domain has reached the limit of ' . self::MAX_HOSTS . ' custom hosts.');
        $drv->createHost($d->name, $v['label'], $v['ips'], $actor);
        $this->log($d, 'dm_host_added', $actor, ['host' => $v['label'] . '.' . $d->name]);
        $this->notifyStaff($d, 'host', $actor);
        return ['hostname' => $v['label'] . '.' . $d->name, 'ips' => $v['ips']];
    }

    public function editHost(Domain $d, string $host, array $ips, array $actor): array
    {
        $this->limited($d, 'host');
        $v = self::validateHost($host, $ips, $d->name);
        $full = $v['label'] . '.' . $d->name;
        $drv = $this->driver($d);
        if (!collect($drv->listHosts($d->name))->contains(fn ($h) => strtolower((string) ($h['hostname'] ?? '')) === $full)) {
            throw new \DomainException('That host no longer exists. Refresh the page.');
        }
        $drv->updateHost($d->name, $full, $v['ips'], $actor);
        $this->log($d, 'dm_host_edited', $actor, ['host' => $full]);
        $this->notifyStaff($d, 'host', $actor);
        return ['hostname' => $full, 'ips' => $v['ips']];
    }
}
