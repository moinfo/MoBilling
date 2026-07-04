<?php

namespace App\Services\Registrar;

use App\Models\Domain;
use App\Models\DomainLog;

/**
 * Nameserver reads/changes for .tz domains, shared by the staff and portal
 * controllers. NSsets are shared registry objects — a set referenced by any
 * other domain is NEVER edited in place; instead a new nsset is created and
 * only this domain repointed. All operations are free EPP calls.
 */
class NameserverService
{
    public function __construct(private DomainRegistrarManager $registrar) {}

    /** @throws \App\Exceptions\RegistrarApiException */
    public function list(Domain $domain): array
    {
        $driver = $this->registrar->driverFor($domain->tenant_id, $domain->id);
        $info = $driver->nssetInfo($domain->nsset_handle);

        return [
            'nsset'       => $domain->nsset_handle,
            'nameservers' => collect($info['nameservers'] ?? [])->pluck('name')->all(),
            'tech'        => $info['tech'] ?? [],
            'shared_with' => $this->sharedWith($domain),
        ];
    }

    /**
     * Apply a new nameserver list. Returns ['changed' => bool, 'nsset' => handle].
     * @param string[] $new  lowercased hostnames
     * @throws \App\Exceptions\RegistrarApiException|\RuntimeException
     */
    public function update(Domain $domain, array $new, array $auditActor): array
    {
        $new = collect($new)->map(fn ($n) => strtolower(trim($n)))->filter()->unique()->values();

        $driver = $this->registrar->driverFor($domain->tenant_id, $domain->id);
        $info = $driver->nssetInfo($domain->nsset_handle);
        $current = collect($info['nameservers'] ?? [])->pluck('name')->map(fn ($n) => strtolower($n))->values();

        if ($new->sort()->values()->all() === $current->sort()->values()->all()) {
            return ['changed' => false, 'nsset' => $domain->nsset_handle];
        }

        $sharedWith = $this->sharedWith($domain);

        if ($sharedWith > 0) {
            // Tech contact: keep the current one, else the domain's registrant.
            $tech = ($info['tech'] ?? []) ?: array_filter([$domain->registrant_handle]);
            if (empty($tech)) {
                throw new \RuntimeException('No registry contact available for the new nameserver set — contact support.');
            }

            $newHandle = 'NSSET-' . strtoupper(bin2hex(random_bytes(4)));
            $driver->nssetCreate(
                $newHandle,
                $new->map(fn ($n) => ['name' => $n, 'addrs' => []])->all(),
                $tech,
            );
            $driver->updateDomain($domain->name, ['nsset_id' => $newHandle]);
            $domain->update(['nsset_handle' => $newHandle]);
        } else {
            $driver->nssetUpdate(
                $domain->nsset_handle,
                $new->diff($current)->map(fn ($n) => ['name' => $n, 'addrs' => []])->values()->all(),
                $current->diff($new)->values()->all(),
            );
        }

        DomainLog::create([
            'tenant_id' => $domain->tenant_id,
            'domain_id' => $domain->id,
            'action'    => 'nameservers_changed',
            'request'   => array_merge([
                'from' => $current->all(),
                'to'   => $new->all(),
                'mode' => $sharedWith > 0 ? 'new_nsset' : 'in_place',
            ], $auditActor),
            'status'    => 'success',
        ]);

        return ['changed' => true, 'nsset' => $domain->fresh()->nsset_handle];
    }

    private function sharedWith(Domain $domain): int
    {
        return Domain::withoutGlobalScopes()
            ->where('nsset_handle', $domain->nsset_handle)
            ->where('id', '!=', $domain->id)
            ->whereIn('status', ['active', 'expired', 'pending'])->count();
    }
}
