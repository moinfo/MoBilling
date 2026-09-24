<?php

namespace App\Services\Registrar;

use App\Contracts\RegistrarDriver;
use App\Exceptions\RegistrarApiException;
use App\Models\RegistrarAccount;

/**
 * Resolves which registrar accreditation a tenant uses (their own row, else
 * the platform row with NULL tenant_id) and builds the matching driver.
 */
class DomainRegistrarManager
{
    public function accountFor(string $tenantId): RegistrarAccount
    {
        $account = RegistrarAccount::where('is_active', true)
            ->where(fn ($q) => $q->where('tenant_id', $tenantId)->orWhereNull('tenant_id'))
            ->orderByRaw('tenant_id IS NULL') // tenant-owned account wins
            ->first();

        if (!$account) {
            throw new RegistrarApiException('resolve', 'No active registrar account configured');
        }

        return $account;
    }

    public function driverFor(string $tenantId, ?string $domainId = null): RegistrarDriver
    {
        $account = $this->accountFor($tenantId);

        return match ($account->driver) {
            'fred_epp' => (new FredHttpDriver($account))->forDomain($domainId),
            default    => throw new RegistrarApiException('resolve', "Unknown registrar driver [{$account->driver}]"),
        };
    }

    /**
     * Name.com is a tenant-owned credential (namecom_accounts), separate from the
     * FRED registrar_accounts resolution above so it can never affect .tz domains.
     */
    public function namecomFor(string $tenantId): NameComDriver
    {
        $account = \App\Models\NameComAccount::withoutGlobalScopes()->where('tenant_id', $tenantId)->first();
        if (!$account) {
            throw new RegistrarApiException('resolve', 'Name.com is not connected. Add your Name.com API credentials under Domains > Name.com.');
        }
        if ($account->status === 'invalid') {
            throw new RegistrarApiException('resolve', 'The stored Name.com credentials were rejected. Update them under Domains > Name.com.');
        }
        return new NameComDriver($account);
    }
}
