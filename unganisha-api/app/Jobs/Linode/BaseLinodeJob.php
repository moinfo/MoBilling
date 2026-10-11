<?php

namespace App\Jobs\Linode;

use App\Models\LinodeResource;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Log;

/**
 * Linode VPS jobs run from billing paths (payment recording) — they must
 * never throw back into billing. A failure sets the resource's status to
 * `failed` (visible in the Servers table) and is logged. Default tries/backoff
 * here suit power actions (idempotent — shutting down an already-off server
 * is a no-op); ProvisionLinodeVpsInstance overrides $tries=1, since creating
 * a VPS spends real money and is NOT safe to blind-retry (see its docblock).
 */
abstract class BaseLinodeJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public int $tries = 3;

    public function backoff(): array
    {
        return [60, 300, 900];
    }

    protected function guard(LinodeResource $resource, \Closure $fn): void
    {
        try {
            $fn();
        } catch (\Throwable $e) {
            $resource->update(['status' => 'failed']);
            Log::error(static::class . " failed for Linode resource {$resource->id}", ['error' => $e->getMessage()]);
        }
    }
}
