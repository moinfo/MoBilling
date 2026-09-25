<?php

namespace App\Services\Hosting;

use App\Jobs\Hosting\ReactivateHostingAccount;
use App\Models\HostingAccount;
use App\Models\ProductService;
use App\Models\ProvisioningLog;
use App\Models\User;
use App\Notifications\HostingBandwidthUpgradeNotification;
use App\Services\WhmService;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Notification;

/**
 * Bandwidth-suspended accounts may upgrade themselves out of the suspension.
 * Everything about that rule lives here: who may upgrade, what a plan's bandwidth
 * limit is (only when WHM's package list really says so), and the single
 * "plan changed -> maybe unsuspend" step used after the package switch.
 */
class BandwidthSuspensionService
{
    /** null = may upgrade/downgrade; otherwise the message to refuse with. */
    public function refusalMessage(HostingAccount $account): ?string
    {
        if ($account->status === 'active') {
            return null;
        }
        if ($account->status !== 'suspended') {
            return 'This hosting account is not active.';
        }
        return match ($account->suspensionReason()) {
            'bandwidth' => null,
            'billing'   => 'Please settle your unpaid invoices first.',
            default     => 'This account is suspended; please contact support.',
        };
    }

    public function isBandwidthSuspended(HostingAccount $account): bool
    {
        return $account->suspensionReason() === 'bandwidth';
    }

    /**
     * Bandwidth limit (bytes) of the WHM package behind a product, ONLY when WHM
     * reports a numeric BWLIMIT for it. null = unknown (or unlimited) — never guessed.
     */
    public function planLimitBytes(ProductService $plan, ?\App\Models\Server $server): ?int
    {
        if (!$plan->cpanel_package || !$server) {
            return null;
        }
        try {
            $packages = Cache::remember("whm_pkg_bw:{$server->id}", 900, function () use ($server) {
                return collect((new WhmService($server))->listPackagesDetailed())
                    ->mapWithKeys(fn ($p) => [$p['name'] => $p['bandwidth_mb']])->all();
            });
        } catch (\Throwable $e) {
            Log::info('Plan bandwidth lookup unavailable', ['error' => $e->getMessage()]);
            return null;
        }
        $mb = $packages[$plan->cpanel_package] ?? null;

        return $mb && $mb > 0 ? (int) $mb * 1048576 : null;
    }

    /** Pull this account's usage/limit from WHM into meta. Returns [used, limit] or null if unavailable. */
    public function refreshBandwidth(HostingAccount $account): ?array
    {
        try {
            $whm = (new WhmService($account->server))->forAccount($account->id);
            $row = collect($whm->bandwidthUsage())
                ->first(fn ($a) => strcasecmp((string) ($a['user'] ?? ''), $account->cpanel_username) === 0);
            if (!$row) {
                return null;
            }
            $used  = (int) ($row['totalbytes'] ?? 0);
            $limit = (int) ($row['limit'] ?? 0);
            $account->update([
                'last_synced_at' => now(),
                'meta' => array_merge($account->meta ?? [], [
                    'bw_used_bytes'  => $used,
                    'bw_limit_bytes' => $limit > 0 ? $limit : null,
                ]),
            ]);

            return [$used, $limit];
        } catch (\Throwable $e) {
            Log::warning('Bandwidth refresh after upgrade failed', ['hosting_account_id' => $account->id, 'error' => $e->getMessage()]);
            return null;
        }
    }

    /**
     * After the WHM package switch of an account that WAS bandwidth-suspended:
     * unsuspend if usage is now under the new limit, else stay suspended and tell staff.
     * Idempotent: only acts while the account is still suspended; staff are told once per package.
     */
    public function afterPackageChange(HostingAccount $account, ?int $fallbackLimitBytes = null): void
    {
        $account = $account->fresh('server');
        if (!$account || $account->status !== 'suspended') {
            return; // already restored (or otherwise not ours to touch)
        }

        $used = (int) ($account->meta['bw_used_bytes'] ?? 0);
        $fresh = $this->refreshBandwidth($account);
        $limit = null;
        if ($fresh) {
            [$used, $limitRaw] = $fresh;
            $limit = $limitRaw > 0 ? $limitRaw : PHP_INT_MAX; // WHM 0 = unlimited
        } elseif ($fallbackLimitBytes) {
            $limit = $fallbackLimitBytes;
        }

        $restored = false;
        if ($limit !== null && $limit > $used) {
            ReactivateHostingAccount::dispatchSync($account);
            $restored = $account->fresh()->status === 'active';
        }

        $marker = 'bw_upgrade_notified:' . $account->package . ':' . ($restored ? 'ok' : 'still');
        $meta = $account->fresh()->meta ?? [];
        if (($meta['bw_upgrade_notified'] ?? null) === $marker) {
            return;
        }
        $account->fresh()->update(['meta' => array_merge($meta, ['bw_upgrade_notified' => $marker])]);

        $this->log($account, $restored ? 'bandwidth_upgrade_reactivated' : 'bandwidth_upgrade_still_suspended', $restored, [
            'bw_used_bytes' => $used, 'bw_limit_bytes' => $limit === PHP_INT_MAX ? 0 : $limit,
        ]);
        $this->notifyStaff($account, $restored);
    }

    private function log(HostingAccount $account, string $action, bool $ok, array $request): void
    {
        try {
            ProvisioningLog::withoutGlobalScopes()->create([
                'tenant_id' => $account->tenant_id, 'hosting_account_id' => $account->id, 'server_id' => $account->server_id,
                'action' => $action, 'request' => $request, 'status' => $ok ? 'success' : 'failed',
                'error' => $ok ? null : 'Usage is still at or above the new plan limit; account left suspended.',
            ]);
        } catch (\Throwable $e) {
            Log::warning('Bandwidth upgrade log failed', ['hosting_account_id' => $account->id]);
        }
    }

    private function notifyStaff(HostingAccount $account, bool $restored): void
    {
        try {
            $staff = User::withPermission($account->tenant_id, 'hosting.change_package');
            if ($staff->isNotEmpty()) {
                Notification::send($staff, new HostingBandwidthUpgradeNotification($account, $restored));
            }
        } catch (\Throwable $e) {
            report($e);
        }
    }
}
