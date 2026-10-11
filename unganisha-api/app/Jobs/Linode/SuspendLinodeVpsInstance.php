<?php

namespace App\Jobs\Linode;

use App\Models\LinodeResource;
use App\Services\Linode\LinodeService;
use Illuminate\Support\Facades\Log;

/**
 * Non-payment / cancellation SUSPENDS the VPS (shuts it down) — it is never
 * deleted automatically. Same design decision as hosting
 * (ClientSubscriptionObserver's docblock): termination stays a manual,
 * permission-gated admin action in Linode Cloud Manager or the Servers tab.
 */
class SuspendLinodeVpsInstance extends BaseLinodeJob
{
    public function __construct(public LinodeResource $resource, public string $reason = 'Unpaid invoice') {}

    public function handle(): void
    {
        $resource = $this->resource->fresh('account');
        if (!$resource || !$resource->account || $resource->type !== 'instance') {
            return;
        }

        $this->guard($resource, function () use ($resource) {
            $svc = new LinodeService($resource->account);
            $live = (string) ($svc->getInstance($resource->remote_id)['status'] ?? '');

            if (in_array($live, LinodeService::BUSY_STATUSES, true)) {
                Log::info("SuspendLinodeVpsInstance: {$resource->label} is busy ({$live}) — will catch up on the next status change.");
                return;
            }
            if ($live === 'running') {
                $svc->powerAction($resource->remote_id, 'shutdown');
                $live = 'shutting_down';
            }
            $resource->update(['status' => $live ?: $resource->status]);
        });
    }
}
