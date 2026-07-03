<?php

namespace App\Jobs\Hosting;

use App\Models\HostingAccount;
use App\Services\WhmService;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Log;

/**
 * Provisioning jobs NEVER throw out of handle(): with the sync queue driver they
 * run inline inside billing requests (e.g. payment recording), and a WHM outage
 * must not break billing. Failures set the account to `failed` (visible in the UI)
 * and hosting:reconcile retries them daily.
 */
abstract class BaseHostingJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public int $tries = 3;

    public function backoff(): array
    {
        return [60, 300, 900];
    }

    protected function whm(HostingAccount $account): WhmService
    {
        return (new WhmService($account->server))->forAccount($account->id);
    }

    protected function guard(HostingAccount $account, \Closure $fn): void
    {
        try {
            $fn();
        } catch (\Throwable $e) {
            $account->update(['status' => 'failed']);
            Log::error(static::class . " failed for hosting account {$account->id}", [
                'error' => $e->getMessage(),
            ]);
        }
    }
}
