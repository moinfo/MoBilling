<?php

namespace App\Console\Commands;

use App\Jobs\Hosting\TerminateHostingAccount;
use App\Models\ClientSubscription;
use App\Models\CronLog;
use App\Models\Tenant;
use Carbon\Carbon;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;

/**
 * WHMCS "Auto Terminate" parity: automatically terminate services that have
 * stayed SUSPENDED past a configured number of days. Destructive (deletes the
 * cPanel account), so it is gated behind config('whmcs.auto_terminate_suspended_days')
 * and DISABLED by default (0). Runs after subscriptions:suspend-unpaid.
 */
class TerminateAbandonedSubscriptions extends Command
{
    protected $signature = 'subscriptions:terminate-abandoned';

    protected $description = 'Terminate services that have remained suspended past the configured auto-terminate window (WHMCS Auto Terminate parity)';

    public function handle(): int
    {
        $startedAt = now();

        $days = (int) config('whmcs.auto_terminate_suspended_days', 0);

        // SAFE DEFAULT: 0 disables the feature. Destructive action stays off
        // until an operator opts in via WHMCS_AUTO_TERMINATE_DAYS.
        if ($days <= 0) {
            $this->info('Auto-terminate disabled (whmcs.auto_terminate_suspended_days = 0). Nothing to do.');
            return self::SUCCESS;
        }

        $cutoff = Carbon::now()->subDays($days);
        $terminated = 0;
        $skipped = 0;

        try {
            // Load all suspended subscriptions (bypass tenant scope). Querying
            // status=suspended makes this idempotent: anything already terminated
            // (or cancelled/active) is naturally excluded.
            $subscriptions = ClientSubscription::withoutGlobalScopes()
                ->whereNull('deleted_at')
                // Parallel mode: WHMCS manages termination of imported services.
                ->when(config('whmcs.parallel_mode'), fn ($q) => $q->whereNull('legacy_id'))
                ->where('status', 'suspended')
                ->get();

            if ($subscriptions->isEmpty()) {
                $this->info('No suspended subscriptions found.');
                $this->logResult($startedAt, 0, 0, $days, 'success');
                return self::SUCCESS;
            }

            $tenantCache = [];

            foreach ($subscriptions as $subscription) {
                $tenantId = $subscription->tenant_id;

                if (!array_key_exists($tenantId, $tenantCache)) {
                    $tenantCache[$tenantId] = Tenant::find($tenantId);
                }
                $tenant = $tenantCache[$tenantId];

                if (!$tenant || !$tenant->hasAccess()) {
                    $skipped++;
                    continue;
                }

                // "Suspended since": prefer the metadata stamp written by the
                // suspend path; fall back to updated_at (which reflects the last
                // status change) when the stamp is absent (pre-existing/manual).
                $suspendedAtRaw = $subscription->metadata['suspended_at'] ?? null;
                $suspendedAt = $suspendedAtRaw
                    ? Carbon::parse($suspendedAtRaw)
                    : $subscription->updated_at;

                if (!$suspendedAt || $suspendedAt->greaterThan($cutoff)) {
                    // Not suspended long enough yet.
                    $skipped++;
                    continue;
                }

                // Terminate the hosting account (destructive, dispatched to queue)
                // then mark the subscription terminated.
                $subscription->loadMissing('hostingAccount');
                if ($subscription->hostingAccount) {
                    TerminateHostingAccount::dispatch($subscription->hostingAccount);
                }

                $subscription->update(['status' => 'terminated']);

                $terminated++;
                $this->info("Terminated: {$subscription->label} (client: {$subscription->client_id}, suspended since {$suspendedAt->toDateString()})");
            }

            $this->info("Done. Terminated: {$terminated}, Skipped: {$skipped}");
            $this->logResult($startedAt, $terminated, $skipped, $days, 'success');

            return self::SUCCESS;
        } catch (\Throwable $e) {
            CronLog::create([
                'tenant_id' => null,
                'command' => $this->signature,
                'description' => 'Failed to terminate abandoned subscriptions',
                'status' => 'failed',
                'error' => $e->getMessage(),
                'started_at' => $startedAt,
                'finished_at' => now(),
            ]);

            $this->error($e->getMessage());
            Log::error('TerminateAbandonedSubscriptions failed', ['error' => $e->getMessage()]);
            return self::FAILURE;
        }
    }

    private function logResult($startedAt, int $terminated, int $skipped, int $days, string $status): void
    {
        CronLog::create([
            'tenant_id' => null,
            'command' => $this->signature,
            'description' => "Terminated {$terminated} subscriptions, skipped {$skipped} (window: {$days} days)",
            'results' => [
                'terminated' => $terminated,
                'skipped' => $skipped,
                'days' => $days,
            ],
            'status' => $status,
            'started_at' => $startedAt,
            'finished_at' => now(),
        ]);
    }
}
