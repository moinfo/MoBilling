<?php

namespace App\Console\Commands;

use App\Exceptions\MikrotikApiException;
use App\Models\MikrotikRouter;
use App\Models\User;
use App\Notifications\RouterStatusChangedNotification;
use App\Services\Mikrotik\RouterOsService;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Notification;

/**
 * Tests every active router's RouterOS API reachability (same call as the
 * "Test Connection" button) and alerts the owning tenant's admin(s) only on
 * a status *change* — down->up or up->down — never on every poll, so a
 * router that's been down for hours doesn't spam. Without this, a router
 * outage is invisible until a customer's purchase fails or someone
 * happens to click "Test Connection" (this is exactly what happened
 * during development: a WireGuard tunnel silently dropped and nobody
 * noticed for hours).
 */
class CheckWifiRouterHealth extends Command
{
    protected $signature = 'wifi:check-router-health';
    protected $description = "Test connectivity to every active MikroTik router and alert tenant admins when one's status changes";

    public function handle(): int
    {
        $routers = MikrotikRouter::withoutGlobalScopes()->where('is_active', true)->get();
        $changed = 0;

        foreach ($routers as $router) {
            $previousStatus = $router->last_test_status;

            try {
                $result = (new RouterOsService($router))->testConnection();
                $router->update([
                    'last_tested_at'    => now(),
                    'last_test_status'  => 'success',
                    'last_test_message' => $result['message'],
                ]);

                if ($previousStatus === 'failed') {
                    $this->alertTenant($router, true, $result['message']);
                    $changed++;
                }
            } catch (MikrotikApiException $e) {
                $router->update([
                    'last_tested_at'    => now(),
                    'last_test_status'  => 'failed',
                    'last_test_message' => $e->getMessage(),
                ]);

                if ($previousStatus !== 'failed') {
                    $this->alertTenant($router, false, $e->getMessage());
                    $changed++;
                }
            }
        }

        $this->info("Checked {$routers->count()} router(s), {$changed} status change(s).");

        return self::SUCCESS;
    }

    private function alertTenant(MikrotikRouter $router, bool $isOnline, string $detail): void
    {
        $admins = User::withoutGlobalScopes()
            ->where('tenant_id', $router->tenant_id)
            ->where('role', 'admin')
            ->where('is_active', true)
            ->get();

        if ($admins->isEmpty()) {
            return;
        }

        Notification::send($admins, new RouterStatusChangedNotification($router, $isOnline, $detail));
    }
}
