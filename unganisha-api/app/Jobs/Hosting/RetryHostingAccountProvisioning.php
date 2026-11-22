<?php

namespace App\Jobs\Hosting;

use App\Models\HostingAccount;
use App\Notifications\HostingAccountProvisionedNotification;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

/**
 * Retries a hosting account stuck in `failed` — e.g. WHM's createacct was
 * rejected (server over its account limit, a transient API error) and the
 * cPanel account was never actually created. Unlike ProvisionHostingAccount
 * (which only ever creates a NEW hosting_accounts row), this reuses the
 * exact domain/username/package already recorded on the existing row, so
 * staff don't have to delete and recreate anything just to try again.
 *
 * A fresh password is generated — the original was never stored (see
 * ProvisionHostingAccount's doc comment) — and the welcome notification is
 * only sent once createacct actually succeeds.
 */
class RetryHostingAccountProvisioning extends BaseHostingJob
{
    public function __construct(public HostingAccount $account) {}

    public function handle(): void
    {
        $account = $this->account->fresh(['subscription.productService', 'subscription.client']);
        if (!$account || $account->status !== 'failed') {
            return; // already retried/resolved since this was dispatched
        }

        $sub = $account->subscription;
        $product = $sub?->productService;
        $password = Str::password(20, symbols: false) . '#9a'; // cPanel-safe strength

        $account->update(['status' => 'pending']);

        $this->guard($account, function () use ($account, $sub, $product, $password) {
            $this->whm($account)->createAccount(
                $account->cpanel_username,
                $account->domain,
                $password,
                $account->package ?? $product?->cpanel_package ?? 'default',
                $sub?->client?->email
            );

            $account->update(['status' => 'active']);

            if ($sub?->client && ($sub->client->email || $sub->client->phone)) {
                try {
                    $sub->client->notify(new HostingAccountProvisionedNotification($account, $password));
                } catch (\Throwable $e) {
                    Log::warning("Retry-provision welcome failed for {$account->id}: {$e->getMessage()}");
                }
            }
        });
    }
}
