<?php

namespace App\Services\Linode;

/**
 * Pure helpers (no network, no DB) that turn a domain's DNS records into
 * "which of our servers does it point to".
 */
class DnsMapping
{
    /** Canonical form so "2600:3c00::1/128" and "2600:3C00:0:0:0:0:0:1" compare equal. */
    public static function normalizeIp(?string $ip): ?string
    {
        if ($ip === null) return null;
        $ip = trim(explode('/', trim($ip))[0]);
        $bin = @inet_pton($ip);
        return $bin === false ? null : inet_ntop($bin);
    }

    /**
     * From a full records listing extract the A/AAAA targets for the apex ("" / "@") and "www".
     * @return array{apex_ips: string[], www_ips: string[]}
     */
    public static function extractAddresses(array $records): array
    {
        $out = ['apex_ips' => [], 'www_ips' => []];
        foreach ($records as $r) {
            if (!in_array(strtoupper((string) ($r['type'] ?? '')), ['A', 'AAAA'], true)) continue;
            $name = strtolower(trim((string) ($r['name'] ?? '')));
            $ip = self::normalizeIp($r['target'] ?? null);
            if ($ip === null) continue;
            if ($name === '' || $name === '@') $out['apex_ips'][] = $ip;
            elseif ($name === 'www') $out['www_ips'][] = $ip;
        }
        $out['apex_ips'] = array_values(array_unique($out['apex_ips']));
        $out['www_ips'] = array_values(array_unique($out['www_ips']));
        return $out;
    }

    /**
     * ip => [instance ids] for the given instances (arrays with id, ipv4[], ipv6).
     * @param iterable $instances each: ['id'=>, 'ipv4'=>array, 'ipv6'=>?string]
     */
    public static function buildIpIndex(iterable $instances): array
    {
        $index = [];
        foreach ($instances as $i) {
            $ips = (array) ($i['ipv4'] ?? []);
            if (!empty($i['ipv6'])) $ips[] = $i['ipv6'];
            foreach ($ips as $ip) {
                $n = self::normalizeIp($ip);
                if ($n !== null) $index[$n][] = $i['id'];
            }
        }
        return $index;
    }

    /**
     * @param array $ipIndex from buildIpIndex
     * @return array{status:string, instance_ids:string[], apex_instance_ids:string[], www_instance_ids:string[], external_ips:string[]}
     *   status: server | external | no_a_record
     */
    public static function match(array $apexIps, array $wwwIps, array $ipIndex): array
    {
        $ids = fn (array $ips) => array_values(array_unique(array_merge(...array_map(fn ($ip) => $ipIndex[$ip] ?? [], $ips) ?: [[]])));
        $apexIds = $ids($apexIps);
        $wwwIds = $ids($wwwIps);
        $all = array_values(array_unique(array_merge($apexIds, $wwwIds)));
        $external = array_values(array_filter(array_unique(array_merge($apexIps, $wwwIps)), fn ($ip) => !isset($ipIndex[$ip])));

        $status = $all ? 'server' : ($external ? 'external' : 'no_a_record');

        return ['status' => $status, 'instance_ids' => $all, 'apex_instance_ids' => $apexIds, 'www_instance_ids' => $wwwIds, 'external_ips' => $external];
    }
}
