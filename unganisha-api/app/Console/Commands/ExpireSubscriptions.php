<?php

namespace App\Console\Commands;

use App\Services\SubscriptionService;
use Illuminate\Console\Command;

class ExpireSubscriptions extends Command
{
    protected $signature = 'subscriptions:expire';

    protected $description = 'Expire active subscriptions that have passed their end date';

    public function handle(): int
    {
        $service = new SubscriptionService();
        $count = $service->expireOverdueSubscriptions();

        $this->info("Expired {$count} subscription(s).");

        return self::SUCCESS;
    }
}
