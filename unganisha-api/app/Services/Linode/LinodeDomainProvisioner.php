<?php

namespace App\Services\Linode;

use App\Exceptions\LinodeApiException;
use App\Models\Domain;
use App\Models\LinodeAccount;
use App\Models\LinodeResource;

/**
 * Shared "add a domain to Linode DNS" logic, used by the staff Add-domain form and by approval of a
 * client's domain request. Only ever creates (POST domain / POST records) - never deletes.
 */
class LinodeDomainProvisioner
{
    /**
     * @return array{resource: LinodeResource, records_created: int, warning: ?string}
     * @throws \InvalidArgumentException user-facing validation problem (422)
     */
    public function add(LinodeAccount $account, string $domain, ?string $soaEmail, ?int $ttl = null, ?LinodeResource $server = null, ?string $clientId = null): array
    {
        if (LinodeResource::where('type', 'domain')->where('label', $domain)->where('status', '!=', 'gone')->exists()) {
            throw new \InvalidArgumentException("$domain is already added to Linode (it exists in your synced domains).");
        }

        $svc = new LinodeService($account);
        try {
            $created = $svc->createDomain($domain, $soaEmail ?? $account->soa_email ?? '', $ttl);
        } catch (LinodeApiException $e) {
            $msg = $e->getMessage();
            if ($e->httpStatus === 400 && stripos($msg, 'already exists') !== false) {
                $msg = "$domain already exists on Linode (possibly in another Linode account, since domain names are unique across Linode). $msg";
            }
            throw new \InvalidArgumentException($msg, 0, $e);
        }

        $attrs = [
            'tenant_id' => $account->tenant_id, 'label' => $domain, 'status' => $created['status'] ?? 'active',
            'meta' => ['type' => 'master', 'soa_email' => $created['soa_email'] ?? null, 'ttl_sec' => $created['ttl_sec'] ?? null],
            'domain_id' => Domain::where('name', $domain)->value('id'), 'synced_at' => now(),
        ];
        if ($clientId) $attrs['client_id'] = $clientId;
        $resource = LinodeResource::updateOrCreate(
            ['linode_account_id' => $account->id, 'type' => 'domain', 'remote_id' => (string) $created['id']],
            $attrs
        );

        $recordsCreated = 0;
        $warning = null;
        if ($server) {
            try {
                $recordsCreated = count($svc->createStandardWebRecords($created['id'], $server->ipv4[0]));
                // Record where it points so the mapping is known before the next DNS refresh.
                $ip = DnsMapping::normalizeIp($server->ipv4[0]);
                $meta = $resource->meta ?? [];
                $meta['dns'] = [
                    'apex_ips' => [$ip], 'www_ips' => [$ip], 'status' => 'server', 'points_to_instance_ids' => [$server->id],
                    'points_to_labels' => [$server->label], 'external_ips' => [], 'fetched_at' => now()->toIso8601String(), 'error' => null,
                ];
                $resource->update(['meta' => $meta]);
            } catch (\InvalidArgumentException | LinodeApiException $e) {
                $warning = 'Domain created, but adding the A records failed: ' . $e->getMessage() . ' You can add them from the Records drawer.';
            }
        }

        return ['resource' => $resource, 'records_created' => $recordsCreated, 'warning' => $warning];
    }
}
