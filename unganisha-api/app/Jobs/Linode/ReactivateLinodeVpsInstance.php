<?php

namespace App\Jobs\Linode;

use App\Models\LinodeResource;
use App\Services\Linode\LinodeService;
use Illuminate\Support\Facades\Log;

class ReactivateLinodeVpsInstance extends BaseLinodeJob
{
    public function __construct(public LinodeResource $resource) {}

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
                Log::info("ReactivateLinodeVpsInstance: {$resource->label} is busy ({$live}) — will catch up on the next status change.");
                return;
            }
            if ($live === 'offline') {
                $svc->powerAction($resource->remote_id, 'boot');
                $live = 'booting';
            }
            $resource->update(['status' => $live ?: $resource->status]);
        });
    }
}
