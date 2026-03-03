<?php

namespace App\Console\Commands;

use App\Models\ClientSubscription;
use App\Models\CronLog;
use App\Models\RecurringInvoiceLog;
use App\Models\Tenant;
use App\Notifications\SubscriptionSuspendedNotification;
use Carbon\Carbon;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;

class SuspendUnpaidSubscriptions extends Command
{
    protected $signature = 'subscriptions:suspend-unpaid';

    protected $description = 'Suspend active client subscriptions whose invoices are unpaid past the grace period';

    public function handle(): int
    {
        $startedAt = now();
        $today = Carbon::today();
        $suspended = 0;
        $skipped = 0;

        try {
            // 1. Load all active subscriptions (bypass tenant scope)
            $subscriptions = ClientSubscription::withoutGlobalScopes()
                ->whereNull('deleted_at')
                ->where('status', 'active')
                ->get();

            if ($subscriptions->isEmpty()) {
                $this->info('No active subscriptions found.');
                $this->logResult($startedAt, 0, 0, 'success');
                return self::SUCCESS;
            }

            // 2. Batch-load the latest recurring invoice log per (tenant_id, client_id, product_service_id)
            $logs = RecurringInvoiceLog::withoutGlobalScopes()
                ->whereNotNull('document_id')
                ->with('document')
                ->orderByDesc('invoice_created_at')
                ->get();

            // Deduplicate: keep only the latest log per subscription key
            $latestLogMap = [];
            foreach ($logs as $log) {
                $key = "{$log->tenant_id}|{$log->client_id}|{$log->product_service_id}";
                if (!isset($latestLogMap[$key])) {
                    $latestLogMap[$key] = $log;
                }
            }

            // 3. Group subscriptions by tenant for hasAccess() check
            $tenantCache = [];

            foreach ($subscriptions as $subscription) {
                $tenantId = $subscription->tenant_id;

                // Cache tenant lookup
                if (!isset($tenantCache[$tenantId])) {
                    $tenantCache[$tenantId] = Tenant::find($tenantId);
                }
                $tenant = $tenantCache[$tenantId];

                if (!$tenant || !$tenant->hasAccess()) {
                    $skipped++;
                    continue;
                }

                $graceDays = $tenant->subscription_grace_days ?? 7;

                // Find the latest invoice log for this subscription
                $key = "{$subscription->tenant_id}|{$subscription->client_id}|{$subscription->product_service_id}";
                $log = $latestLogMap[$key] ?? null;

                if (!$log || !$log->document) {
                    $skipped++;
                    continue;
                }

                $document = $log->document;

                // Check: is the document unpaid and past the grace period?
                $isUnpaid = !in_array($document->status, ['paid', 'draft']);
                $dueDate = $document->due_date;

                if (!$isUnpaid || !$dueDate) {
                    continue;
                }

                // Feature launch date: don't retroactively suspend for invoices
                // due before this date. Grace period starts from whichever is later.
                $featureLaunch = Carbon::parse('2026-03-01');
                $effectiveStart = $dueDate->greaterThan($featureLaunch) ? $dueDate : $featureLaunch;
                $graceCutoff = $effectiveStart->copy()->addDays($graceDays);

                if ($today->greaterThan($graceCutoff)) {
                    // Suspend the subscription
                    $subscription->update(['status' => 'suspended']);

                    // Notify the client (don't let notification failure abort the batch)
                    try {
                        $subscription->loadMissing('client');
                        if ($subscription->client?->email) {
                            $subscription->client->notify(
                                new SubscriptionSuspendedNotification($subscription, $document, $tenant)
                            );
                        }
                    } catch (\Throwable $e) {
                        Log::warning("SuspendUnpaidSubscriptions: notification failed for subscription {$subscription->id}", [
                            'error' => $e->getMessage(),
                        ]);
                    }

                    $suspended++;
                    $this->info("Suspended: {$subscription->label} (client: {$subscription->client_id}, invoice: {$document->document_number})");
                }
            }

            $this->info("Done. Suspended: {$suspended}, Skipped: {$skipped}");
            $this->logResult($startedAt, $suspended, $skipped, 'success');

            return self::SUCCESS;
        } catch (\Throwable $e) {
            CronLog::create([
                'tenant_id' => null,
                'command' => $this->signature,
                'description' => 'Failed to suspend unpaid subscriptions',
                'status' => 'failed',
                'error' => $e->getMessage(),
                'started_at' => $startedAt,
                'finished_at' => now(),
            ]);

            $this->error($e->getMessage());
            Log::error('SuspendUnpaidSubscriptions failed', ['error' => $e->getMessage()]);
            return self::FAILURE;
        }
    }

    private function logResult($startedAt, int $suspended, int $skipped, string $status): void
    {
        CronLog::create([
            'tenant_id' => null,
            'command' => $this->signature,
            'description' => "Suspended {$suspended} subscriptions, skipped {$skipped}",
            'results' => [
                'suspended' => $suspended,
                'skipped' => $skipped,
            ],
            'status' => $status,
            'started_at' => $startedAt,
            'finished_at' => now(),
        ]);
    }
}
