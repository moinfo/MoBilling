<?php

namespace App\Services\Registrar;

use App\Exceptions\NameComApiException;
use App\Exceptions\RegistrarApiException;
use App\Models\Client;
use App\Models\Domain;
use App\Models\DomainLog;
use App\Models\NameComAccount;
use Carbon\Carbon;

/**
 * Domain-level Name.com operations shared by the staff and portal controllers:
 * live nameserver read, guarded nameserver change, read-only sync, and linking.
 * Linked domains carry meta.namecom (and meta.unmanaged = true, so renewals and
 * auto-renew keep following the existing external-registrar flow).
 */
class NameComDomainService
{
    public const LINODE_NAMESERVERS = ['ns1.linode.com', 'ns2.linode.com', 'ns3.linode.com', 'ns4.linode.com', 'ns5.linode.com'];
    public const MAX_CHANGES_PER_DAY = 5;

    public function __construct(private DomainRegistrarManager $registrar) {}

    public static function isLinked(Domain $domain): bool
    {
        return !empty($domain->meta['namecom']);
    }

    /** @throws \App\Exceptions\RegistrarApiException|NameComApiException */
    public static function original(Domain $domain): array
    {
        return $domain->meta['namecom']['original_nameservers'] ?? [];
    }

    public function nameservers(Domain $domain): array
    {
        return $this->registrar->namecomForDomain($domain)->nameservers($domain->name);
    }

    /**
     * @param string[] $new
     * @return array{changed: bool, nameservers: string[]}
     * @throws \InvalidArgumentException validation
     * @throws \DomainException rate limited
     */
    public function updateNameservers(Domain $domain, array $new, array $actor): array
    {
        $new = NameComDriver::validateNameservers($new);

        $recent = DomainLog::where('domain_id', $domain->id)
            ->where('action', 'namecom_nameservers_changed')->where('status', 'success')
            ->where('created_at', '>=', now()->subDay())->count();
        if ($recent >= self::MAX_CHANGES_PER_DAY) {
            throw new \DomainException('Nameserver changes for this domain are limited to ' . self::MAX_CHANGES_PER_DAY . ' per day. Try again tomorrow.');
        }

        $driver = $this->registrar->namecomForDomain($domain);
        $current = $driver->nameservers($domain->name);

        $a = $new; $b = $current; sort($a); sort($b);
        if ($a === $b) {
            return ['changed' => false, 'nameservers' => $current];
        }

        $res = $driver->setNameservers($domain->name, $new, $current, $actor);
        $applied = NameComDriver::extractNameservers($res) ?: $new;

        DomainLog::create([
            'tenant_id' => $domain->tenant_id,
            'domain_id' => $domain->id,
            'action'    => 'namecom_nameservers_changed',
            'request'   => array_merge(['from' => $current, 'to' => $new, 'via' => 'namecom'], $actor),
            'status'    => 'success',
        ]);
        $this->touchMeta($domain, ['nameservers' => $applied]);

        return ['changed' => true, 'nameservers' => $applied];
    }

    /** Whether this row is served by Name.com (linked, or ordered through the Name.com sales flow). */
    public static function isNameComDomain(Domain $domain): bool
    {
        return !empty($domain->meta['namecom']) || ($domain->meta['registrar'] ?? null) === 'namecom';
    }

    /** Label of the Name.com API account this domain uses (its own, else the tenant default). Staff-only. */
    public static function accountLabel(Domain $domain): ?string
    {
        $account = NameComAccount::findFor($domain->tenant_id, $domain->meta['namecom']['account_id'] ?? null)
            ?? NameComAccount::defaultFor($domain->tenant_id);
        return $account?->displayLabel();
    }

    /**
     * Live read-only facts from Name.com (GET /core/v1/domains/{name}); only fields the API documents.
     * @throws NameComApiException|RegistrarApiException
     */
    public function facts(Domain $domain): array
    {
        return self::normalizeFacts($this->registrar->namecomForDomain($domain)->getDomain($domain->name));
    }

    public static function normalizeFacts(array $info): array
    {
        $flag = fn ($k) => array_key_exists($k, $info) && $info[$k] !== null ? (bool) $info[$k] : null;
        return [
            'expires_at'               => substr((string) ($info['expireDate'] ?? ''), 0, 10) ?: null,
            'created_at'               => substr((string) ($info['createDate'] ?? ''), 0, 10) ?: null,
            'locked'                   => $flag('locked'),
            'autorenew'                => $flag('autorenewEnabled'),
            'privacy'                  => $flag('privacyEnabled'),
            'locks'                    => array_values(array_filter((array) ($info['locks'] ?? []), 'is_string')),
            'transfer_lock_expires_at' => substr((string) ($info['transferLockExpiresAt'] ?? ''), 0, 10) ?: null,
            'nameservers'              => NameComDriver::extractNameservers($info),
        ];
    }

    /** Read-only refresh of expiry/status/nameservers from Name.com. Writes an activity-log row (success or failure). */
    public function sync(Domain $domain): Domain
    {
        try {
            $info = $this->registrar->namecomForDomain($domain)->getDomain($domain->name);
        } catch (NameComApiException | RegistrarApiException $e) {
            DomainLog::create([
                'tenant_id' => $domain->tenant_id, 'domain_id' => $domain->id, 'action' => 'namecom_synced',
                'request' => ['via' => 'namecom', 'by_user' => auth()->id()], 'status' => 'failed', 'error' => mb_substr($e->getMessage(), 0, 500),
            ]);
            throw $e;
        }
        $before = ['expires_at' => $domain->expires_at?->toDateString(), 'status' => $domain->status];
        $this->applyInfo($domain, $info);
        $fresh = $domain->fresh();
        DomainLog::create([
            'tenant_id' => $domain->tenant_id, 'domain_id' => $domain->id, 'action' => 'namecom_synced',
            'request' => ['via' => 'namecom', 'by_user' => auth()->id(), 'from' => $before,
                'to' => ['expires_at' => $fresh->expires_at?->toDateString(), 'status' => $fresh->status]],
            'status' => 'success',
        ]);
        return $fresh;
    }

    /**
     * Link (or upgrade an existing unmanaged row of) a Name.com domain to a client.
     * @throws \InvalidArgumentException|\DomainException
     */
    public function link(string $tenantId, string $name, string $clientId, array $actor, ?string $accountId = null): Domain
    {
        $name = NameComDriver::validateDomainName($name);
        if (!Client::withoutGlobalScopes()->where('tenant_id', $tenantId)->where('id', $clientId)->exists()) {
            throw new \InvalidArgumentException('That client does not belong to your business.');
        }

        $account = $accountId ? NameComAccount::findFor($tenantId, $accountId) : NameComAccount::defaultFor($tenantId);
        if (!$account) throw new \InvalidArgumentException('That Name.com account does not exist.');
        $info = $this->registrar->namecomFor($tenantId, $account->id)->getDomain($name); // source of truth: never trust the browser
        if (strtolower((string) ($info['domainName'] ?? $name)) !== $name) {
            throw new \DomainException('Name.com returned a different domain than requested.');
        }

        $existing = Domain::withoutGlobalScopes()->where('name', $name)->whereNotIn('status', ['cancelled', 'transferred_out'])->first();
        if ($existing && $existing->tenant_id !== $tenantId) {
            throw new \DomainException('This domain is already registered in another account.');
        }
        if ($existing && $existing->registrar_account_id && !($existing->meta['unmanaged'] ?? false)) {
            throw new \DomainException('This domain is managed through the .tz registry and cannot be linked to Name.com.');
        }

        $expires = substr((string) ($info['expireDate'] ?? ''), 0, 10) ?: null;
        $attrs = [
            'tenant_id'  => $tenantId,
            'client_id'  => $clientId,
            'name'       => $name,
            'status'     => $expires && Carbon::parse($expires)->isPast() ? 'expired' : 'active',
            'expires_at' => $expires,
        ];
        $created = substr((string) ($info['createDate'] ?? ''), 0, 10) ?: null;
        if ($created) $attrs['registered_at'] = $created;

        $nc = $this->metaFrom($info);
        $nc['account_id'] = $account->id; // which Name.com login owns this domain
        // Remember the nameservers at first link so "use original" can restore them.
        $nc['original_nameservers'] = $existing?->meta['namecom']['original_nameservers'] ?? $nc['nameservers'];
        $meta = array_merge($existing?->meta ?? [], ['unmanaged' => true, 'namecom' => $nc]);

        if ($existing) {
            $existing->update($attrs + ['meta' => $meta]);
            $domain = $existing->fresh();
            $upgraded = true;
        } else {
            $domain = Domain::reviveOrCreate($attrs + ['auto_renew' => false, 'meta' => $meta + ['added_existing' => true]]);
            $upgraded = false;
        }

        DomainLog::create([
            'tenant_id' => $tenantId,
            'domain_id' => $domain->id,
            'action'    => 'namecom_linked',
            'request'   => array_merge(['client_id' => $clientId, 'upgraded_existing' => $upgraded, 'account' => $account->displayLabel()], $actor),
            'status'    => 'success',
        ]);

        return $domain;
    }

    private function applyInfo(Domain $domain, array $info): void
    {
        $expires = substr((string) ($info['expireDate'] ?? ''), 0, 10) ?: null;
        $update = ['meta' => array_merge($domain->meta ?? [], ['namecom' => array_merge($domain->meta['namecom'] ?? [], $this->metaFrom($info))])];
        if ($expires) {
            $update['expires_at'] = $expires;
            if (in_array($domain->status, ['active', 'expired'], true)) {
                $update['status'] = Carbon::parse($expires)->isPast() ? 'expired' : 'active';
            }
        }
        $created = substr((string) ($info['createDate'] ?? ''), 0, 10) ?: null;
        if ($created) $update['registered_at'] = $created;
        $domain->update($update);
    }

    private function touchMeta(Domain $domain, array $extra): void
    {
        $meta = $domain->meta ?? [];
        $meta['namecom'] = array_merge($meta['namecom'] ?? [], $extra, ['synced_at' => now()->toIso8601String()]);
        $domain->update(['meta' => $meta]);
    }

    private function metaFrom(array $info): array
    {
        return [
            'nameservers' => NameComDriver::extractNameservers($info),
            'locked'      => $info['locked'] ?? null,
            'autorenew'   => $info['autorenewEnabled'] ?? null,
            'privacy'     => $info['privacyEnabled'] ?? null,
            'synced_at'   => now()->toIso8601String(),
        ];
    }
}
