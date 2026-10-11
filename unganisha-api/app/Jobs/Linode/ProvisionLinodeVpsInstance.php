<?php

namespace App\Jobs\Linode;

use App\Models\ClientSubscription;
use App\Models\LinodeAccount;
use App\Models\LinodeResource;
use App\Notifications\LinodeVpsProvisionedNotification;
use App\Services\Linode\LinodeService;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

/**
 * Creates a brand-new Linode VPS — real registrar-style money is spent at
 * Linode the moment createInstance() succeeds. Mirrors
 * App\Jobs\Domains\RegisterDomainJob: $tries=1, never blind-retried, because
 * a retried job would create a SECOND billable VPS rather than safely no-op
 * (unlike ReactivateLinodeVpsInstance/SuspendLinodeVpsInstance, which only
 * toggle power state on an already-existing instance).
 */
class ProvisionLinodeVpsInstance extends BaseLinodeJob
{
    public int $tries = 1;

    public function __construct(public ClientSubscription $subscription) {}

    public function handle(): void
    {
        $sub = $this->subscription->fresh(['productService', 'client']);
        $product = $sub?->productService;

        if (!$sub || !$product || $product->provisioning_type !== 'linode_vps') {
            return;
        }
        if ($sub->linodeResource()->exists()) {
            return; // already provisioned — idempotent
        }
        if (!$product->linode_type || !$product->linode_region) {
            Log::error("ProvisionLinodeVpsInstance: product {$product->id} is missing linode_type/linode_region — subscription {$sub->id} not provisioned");
            return;
        }

        $account = LinodeAccount::where('tenant_id', $sub->tenant_id)->where('status', 'active')->orderBy('created_at')->first();
        if (!$account) {
            Log::error("ProvisionLinodeVpsInstance: no active Linode account for tenant {$sub->tenant_id} — subscription {$sub->id} not provisioned");
            return;
        }

        $label = $this->labelFor($sub);
        $rootPass = Str::password(24);

        try {
            $instance = (new LinodeService($account))->createInstance(
                $product->linode_type, $product->linode_region, $product->linode_image ?: 'linode/ubuntu22.04', $rootPass, $label
            );

            $resource = LinodeResource::create([
                'tenant_id'              => $sub->tenant_id,
                'linode_account_id'      => $account->id,
                'type'                   => 'instance',
                'remote_id'              => (string) $instance['id'],
                'label'                  => $instance['label'] ?? $label,
                'status'                 => $instance['status'] ?? 'provisioning',
                'region'                 => $instance['region'] ?? $product->linode_region,
                'plan'                   => $instance['type'] ?? $product->linode_type,
                'ipv4'                   => $instance['ipv4'] ?? [],
                'ipv6'                   => $instance['ipv6'] ?? null,
                'tags'                   => $instance['tags'] ?? [],
                'meta'                   => ['image' => $instance['image'] ?? $product->linode_image, 'created' => $instance['created'] ?? null, 'auto_provisioned' => true],
                'client_id'              => $sub->client_id,
                'client_subscription_id' => $sub->id,
                'synced_at'              => now(),
            ]);
        } catch (\Throwable $e) {
            Log::error("ProvisionLinodeVpsInstance failed for subscription {$sub->id}: {$e->getMessage()}");
            return;
        }

        if ($sub->client && ($sub->client->email || $sub->client->phone)) {
            try {
                $sub->client->notify(new LinodeVpsProvisionedNotification($resource, $rootPass));
            } catch (\Throwable $e) {
                Log::warning("Linode VPS welcome notification failed for {$resource->id}: {$e->getMessage()}");
            }
        }
    }

    /** Linode labels: 3-64 chars, alphanumeric/._- only, must start/end alphanumeric. */
    private function labelFor(ClientSubscription $sub): string
    {
        $base = Str::slug($sub->label ?: ($sub->client?->name ?: 'vps'), '-');
        $base = rtrim(substr($base, 0, 40), '-') ?: 'vps';
        if (strlen($base) < 3) $base = 'vps';

        return $base . '-' . substr($sub->id, 0, 8);
    }
}
