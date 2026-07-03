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
}
