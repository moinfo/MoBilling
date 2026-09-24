<?php

namespace App\Services\Registrar;

use App\Models\Domain;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\Http;

/**
 * Staff-only: which registrar sponsors a non-.tz domain, via PUBLIC RDAP (read-only, no credentials).
 * .com/.net -> Verisign RDAP, .org -> Public Interest Registry RDAP. The registrar is the entity with
 * role "registrar"; IANA id 625 = Name.com, Inc. Result is cached in meta.registrar_lookup and refreshed
 * at most weekly (errors retry after a few hours, never in a loop). Never exposed to the portal.
 */
class DomainRegistrarLookup
{
    public const NAMECOM_IANA = '625';
    public const TTL_DAYS = 7;
    public const ERROR_RETRY_HOURS = 6;

    /** Gap between lookups in a bulk run (ms). Tests set 0. */
    public static int $gapMs = 250;

    private const ENDPOINTS = [
        'com' => 'https://rdap.verisign.com/com/v1/domain/',
        'net' => 'https://rdap.verisign.com/net/v1/domain/',
        'org' => 'https://rdap.publicinterestregistry.org/rdap/domain/',
    ];

    public static function endpoint(string $name): ?string
    {
        $tld = strtolower(substr(strrchr($name, '.') ?: '', 1));
        return isset(self::ENDPOINTS[$tld]) ? self::ENDPOINTS[$tld] . $name : null;
    }

    /** Non-.tz domains that are not served by Name.com (not linked, not ordered through it), still in play. */
    public static function scopeUnlinked(Builder $q): Builder
    {
        return $q->where('name', 'not like', '%.tz')
            ->whereNotIn('status', ['cancelled', 'transferred_out', 'failed'])
            ->whereNull('meta->namecom')
            ->where(fn ($w) => $w->whereNull('meta->registrar')->orWhere('meta->registrar', '!=', 'namecom'));
    }

    public static function isFresh(Domain $d): bool
    {
        $l = $d->meta['registrar_lookup'] ?? null;
        if (!$l || empty($l['checked_at'])) return false;
        $at = \Carbon\Carbon::parse($l['checked_at']);
        return ($l['kind'] ?? 'unknown') === 'unknown' && !empty($l['error'])
            ? $at->gt(now()->subHours(self::ERROR_RETRY_HOURS))
            : $at->gt(now()->subDays(self::TTL_DAYS));
    }

    /** Never throws. @return array{kind: string, name: ?string, iana_id: ?string, checked_at: string, error?: string} */
    public function lookup(Domain $domain, bool $force = false): array
    {
        if (!$force && self::isFresh($domain)) return $domain->meta['registrar_lookup'];

        $res = ['kind' => 'unknown', 'name' => null, 'iana_id' => null, 'checked_at' => now()->toIso8601String()];
        $url = self::endpoint($domain->name);
        if (!$url) {
            $res['error'] = 'No public registry lookup for this extension.';
        } else {
            try {
                $r = Http::acceptJson()->timeout(8)->connectTimeout(5)->get($url);
                if ($r->status() === 404) {
                    $res['error'] = 'Not found in the public registry.';
                } elseif (!$r->successful()) {
                    $res['error'] = 'Registry lookup failed (HTTP ' . $r->status() . ').';
                } else {
                    [$name, $iana] = self::parseRegistrar($r->json() ?? []);
                    if ($name === null && $iana === null) {
                        $res['error'] = 'The registry did not name a registrar.';
                    } else {
                        $res['name'] = $name;
                        $res['iana_id'] = $iana;
                        $res['kind'] = ($iana === self::NAMECOM_IANA || ($name !== null && stripos($name, 'name.com') !== false)) ? 'namecom' : 'other';
                    }
                }
            } catch (\Throwable $e) {
                $res['error'] = 'Could not reach the public registry.';
            }
        }

        $meta = $domain->meta ?? [];
        $meta['registrar_lookup'] = $res;
        $domain->update(['meta' => $meta]);
        return $res;
    }

    /** @return array{0: ?string, 1: ?string} registrar name, IANA id */
    public static function parseRegistrar(array $json): array
    {
        foreach ((array) ($json['entities'] ?? []) as $e) {
            if (!in_array('registrar', (array) ($e['roles'] ?? []), true)) continue;
            $iana = null;
            foreach ((array) ($e['publicIds'] ?? []) as $p) {
                if (stripos((string) ($p['type'] ?? ''), 'IANA') !== false) $iana = (string) ($p['identifier'] ?? '') ?: null;
            }
            $iana ??= isset($e['handle']) && ctype_digit((string) $e['handle']) ? (string) $e['handle'] : null;
            $name = null;
            foreach ((array) ($e['vcardArray'][1] ?? []) as $prop) {
                if (($prop[0] ?? null) === 'fn') $name = trim((string) ($prop[3] ?? '')) ?: null;
            }
            return [$name, $iana];
        }
        return [null, null];
    }

    /**
     * Staff view of where a domain lives. kind: tznic | namecom (linked) | namecom_unlinked | other | unchecked.
     * @param array<string,string> $accountLabels account id => label (pass once to avoid per-row queries)
     */
    public static function view(Domain $d, array $accountLabels = [], ?string $defaultAccountId = null): array
    {
        $l = $d->meta['registrar_lookup'] ?? null;
        $base = ['lookup' => $l ? ['kind' => $l['kind'] ?? 'unknown', 'name' => $l['name'] ?? null, 'iana_id' => $l['iana_id'] ?? null, 'checked_at' => $l['checked_at'] ?? null, 'error' => $l['error'] ?? null] : null];
        if (NameComDomainService::isNameComDomain($d)) {
            $id = $d->meta['namecom']['account_id'] ?? $defaultAccountId;
            return $base + ['kind' => 'namecom', 'label' => 'Name.com', 'account' => $id ? ($accountLabels[$id] ?? null) : null,
                'synced_at' => $d->meta['namecom']['synced_at'] ?? null, 'sync_error' => $d->meta['namecom']['last_sync_error'] ?? null];
        }
        if (str_ends_with($d->name, '.tz')) return $base + ['kind' => 'tznic', 'label' => 'TZNIC'];
        return match ($l['kind'] ?? null) {
            'namecom' => $base + ['kind' => 'namecom_unlinked', 'label' => 'At Name.com, not linked'],
            'other'   => $base + ['kind' => 'other', 'label' => $l['name'] ?? 'Other registrar'],
            default   => $base + ['kind' => 'unchecked', 'label' => 'Unmanaged'],
        };
    }
}
