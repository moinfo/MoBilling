<?php

namespace App\Console\Commands;

use App\Models\CronLog;
use App\Services\SubscriptionService;
use Illuminate\Console\Command;

class ExpireSubscriptions extends Command
{
    protected $signature = 'subscriptions:expire';

    protected $description = 'Expire active subscriptions that have passed their end date';

    public function handle(): int
    {
        $startedAt = now();

        try {
            $service = new SubscriptionService();
            $count = $service->expireOverdueSubscriptions();

            $this->info("Expired {$count} subscription(s).");

            CronLog::create([
                'tenant_id' => null,
                'command' => $this->signature,
                'description' => "Expired {$count} subscription(s)",
                'results' => ['subscriptions_expired' => $count],
                'status' => 'success',
                'started_at' => $startedAt,
                'finished_at' => now(),
            ]);

            return self::SUCCESS;
        } catch (\Throwable $e) {
            CronLog::create([
                'tenant_id' => null,
                'command' => $this->signature,
                'description' => 'Failed to expire subscriptions',
                'status' => 'failed',
                'error' => $e->getMessage(),
                'started_at' => $startedAt,
                'finished_at' => now(),
            ]);

            $this->error($e->getMessage());
            return self::FAILURE;
        }
    }
}
