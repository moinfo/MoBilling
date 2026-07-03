<?php

namespace App\Jobs\Hosting;

use App\Models\ClientSubscription;
use App\Models\HostingAccount;
use App\Notifications\HostingAccountProvisionedNotification;
use App\Services\WhmService;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

class ProvisionHostingAccount extends BaseHostingJob
{
    public function __construct(public ClientSubscription $subscription) {}

    public function handle(): void
    {
        $sub     = $this->subscription->fresh(['productService.server', 'client']);
        $product = $sub?->productService;
        $server  = $product?->server;

        if (!$sub || !$product || !$server || $product->provisioning_type !== 'whm_cpanel') {
            return;
        }
        if ($sub->hostingAccount()->exists()) {
            return; // already provisioned/adopted
        }

        $meta   = $sub->metadata ?? [];
        $domain = $meta['domain'] ?? $sub->label;
        if (!$domain) {
            Log::warning("ProvisionHostingAccount: subscription {$sub->id} has no domain — skipped");
            return;
        }

        // Imported-from-WHMCS services already exist on the server — adopt, don't create.
        if (!empty($meta['cpanel_username'])) {
            HostingAccount::create([
                'tenant_id'              => $sub->tenant_id,
                'client_subscription_id' => $sub->id,
                'server_id'              => $server->id,
                'domain'                 => $domain,
                'cpanel_username'        => $meta['cpanel_username'],
                'package'                => $product->cpanel_package,
                'status'                 => $sub->status === 'suspended' ? 'suspended' : 'active',
                'meta'                   => ['adopted_from_whmcs' => true],
            ]);
            return;
        }

        $username = $this->usernameFor($domain, $server->id);
        $password = Str::password(20, symbols: false) . '#9a'; // cPanel-safe strength

        $account = HostingAccount::create([
            'tenant_id'              => $sub->tenant_id,
            'client_subscription_id' => $sub->id,
            'server_id'              => $server->id,
            'domain'                 => $domain,
            'cpanel_username'        => $username,
            'package'                => $product->cpanel_package,
            'status'                 => 'pending',
        ]);

        $this->guard($account, function () use ($account, $sub, $product, $username, $domain, $password) {
            $this->whm($account)->createAccount(
                $username, $domain, $password,
                $product->cpanel_package ?? 'default',
                $sub->client?->email
            );

            $account->update(['status' => 'active']);

            // Credentials are sent once and never stored.
            if ($sub->client?->email) {
                try {
                    $sub->client->notify(new HostingAccountProvisionedNotification($account, $password));
                } catch (\Throwable $e) {
                    Log::warning("Provision welcome email failed for {$account->id}: {$e->getMessage()}");
                }
            }
        });
    }

    /** WHM username rules: starts with a letter, alphanumeric, max 16 chars, unique per server. */
    private function usernameFor(string $domain, string $serverId): string
    {
        $base = substr(preg_replace('/[^a-z0-9]/', '', strtolower(explode('.', $domain)[0])), 0, 12) ?: 'site';
        if (!preg_match('/^[a-z]/', $base)) {
            $base = 'c' . substr($base, 0, 11);
        }

        $candidate = $base;
        $i = 1;
        while (HostingAccount::withoutGlobalScopes()
            ->where('server_id', $serverId)->where('cpanel_username', $candidate)->exists()) {
            $candidate = substr($base, 0, 12) . $i++;
        }

        return $candidate;
    }
}
