<?php

namespace App\Services;

use App\Models\ClientSubscription;
use App\Models\Domain;
use App\Models\DomainTld;
use App\Models\NameComSettings;
use App\Models\Tenant;
use App\Models\User;
use App\Notifications\TenantWalletHoldNotification;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Notification;

/**
 * Wallet gate for white-label reseller tenants (Tenant::is_wallet_gated).
 * Sits in front of the two existing auto-provisioning hook points —
 * ClientSubscriptionObserver (hosting/email WHM accounts) and
 * DocumentObserver (domain register/transfer/renew) — and decides whether
 * the ALREADY-EXISTING dispatch of those jobs may proceed. A normal tenant
 * (is_wallet_gated = false, which is every tenant except ones provisioned
 * from an approved ResellerApplication) is untouched: every method here
 * returns true immediately for it, so nothing about its behaviour changes.
 *
 * On hold, the subscription/domain's own metadata gets a `wallet_hold` flag
 * (never a new status value) and nothing else happens — no WHM/registrar
 * call of any kind. TenantWalletService::topUp() calls retryHeld() right
 * after a successful top-up to fulfil whatever it now covers, oldest first.
 */
class TenantWalletGateService
{
    public function __construct(private TenantWalletService $wallet) {}

    public function isGated(Tenant $tenant): bool
    {
        return (bool) $tenant->is_wallet_gated;
    }

    // ─────────────────────────── hosting / email ───────────────────────────

    /** True = the caller may proceed with ProvisionHostingAccount::dispatch($sub) exactly as before. */
    public function allowHostingProvision(ClientSubscription $sub): bool
    {
        $tenant = Tenant::withoutGlobalScopes()->find($sub->tenant_id);
        if (!$tenant || !$this->isGated($tenant)) {
            return true;
        }

        if ($this->wallet->alreadyDebited(ClientSubscription::class, $sub->id)) {
            $this->clearHostingHold($sub);
            return true;
        }

        $product = $sub->productService()->withoutGlobalScopes()->first();
        $label = $product?->name ?? 'Hosting service';
        $cost = $product?->cost_price; // $hidden only affects serialization, not attribute access

        if ($cost === null) {
            $this->holdHosting($sub, 'unknown_cost');
            $this->notifyTenant($tenant, $label, 'unknown_cost');
            Log::warning('TenantWalletGate: hosting provision held — no cost_price set', ['subscription_id' => $sub->id, 'product_id' => $product?->id]);
            return false;
        }

        $amount = round((float) $cost * max(1, (int) $sub->quantity), 2);
        $ok = $this->wallet->debit($tenant, $amount, ClientSubscription::class, $sub->id, "hosting-provision:{$sub->id}", "Hosting provision — {$label}");

        if (!$ok) {
            $this->holdHosting($sub, 'insufficient_balance', $amount);
            $this->notifyTenant($tenant, $label, 'insufficient_balance', $amount, $this->wallet->balance($tenant));
            return false;
        }

        $this->clearHostingHold($sub);
        return true;
    }

    private function holdHosting(ClientSubscription $sub, string $reason, ?float $amount = null): void
    {
        $meta = $sub->metadata ?? [];
        $meta['wallet_hold'] = ['reason' => $reason, 'amount_needed' => $amount, 'at' => now()->toIso8601String()];
        $sub->update(['metadata' => $meta]);
    }

    private function clearHostingHold(ClientSubscription $sub): void
    {
        if (!empty($sub->metadata['wallet_hold'] ?? null)) {
            $meta = $sub->metadata;
            unset($meta['wallet_hold']);
            $sub->update(['metadata' => $meta]);
        }
    }

    // ─────────────────────────────── domains ───────────────────────────────

    /** True = the caller may proceed with Register/Transfer/RenewDomainJob::dispatch($domain) exactly as before. */
    public function allowDomainFulfillment(Domain $domain): bool
    {
        $tenant = Tenant::withoutGlobalScopes()->find($domain->tenant_id);
        if (!$tenant || !$this->isGated($tenant)) {
            return true;
        }

        if ($this->wallet->alreadyDebited(Domain::class, $domain->id)) {
            $this->clearDomainHold($domain);
            return true;
        }

        $action = $domain->meta['pending_action'] ?? null;
        $years = max(1, (int) ($domain->meta['pending_years'] ?? 1));
        $cost = $this->domainCostBasis($tenant->id, $domain->name, $action);

        if ($cost === null) {
            $this->holdDomain($domain, 'unknown_cost');
            $this->notifyTenant($tenant, "Domain {$action} — {$domain->name}", 'unknown_cost');
            Log::warning('TenantWalletGate: domain fulfillment held — no wholesale cost source', ['domain_id' => $domain->id, 'name' => $domain->name]);
            return false;
        }

        $amount = round($cost * $years, 2);
        $ok = $this->wallet->debit($tenant, $amount, Domain::class, $domain->id, "domain-{$action}:{$domain->id}", "Domain {$action} — {$domain->name} ({$years} yr)");

        if (!$ok) {
            $this->holdDomain($domain, 'insufficient_balance', $amount);
            $this->notifyTenant($tenant, "Domain {$action} — {$domain->name}", 'insufficient_balance', $amount, $this->wallet->balance($tenant));
            return false;
        }

        $this->clearDomainHold($domain);
        return true;
    }

    /**
     * Wholesale unit cost (per year, local currency) for a domain action, or
     * null when no real cost source exists — Name.com TLDs have real usd
     * cost fields (usd_register/usd_renew) converted at the tenant's own
     * Name.com FX rate; FRED (.tz) TLDs have no wholesale-cost field
     * anywhere in this codebase, so they always return null here (the gate
     * then holds rather than ever guessing or provisioning for free).
     */
    private function domainCostBasis(string $tenantId, string $domainName, ?string $action): ?float
    {
        $tld = strtolower(explode('.', $domainName, 2)[1] ?? '');
        $row = DomainTld::where('tenant_id', $tenantId)->where('tld', $tld)->where('registrar', 'namecom')->first()
            ?? DomainTld::whereNull('tenant_id')->where('tld', $tld)->where('registrar', 'namecom')->first();

        if (!$row) {
            return null; // FRED / unmanaged — no wholesale-cost field exists
        }

        $usd = $action === 'renew' ? $row->usd_renew : $row->usd_register;
        if ($usd === null) {
            return null;
        }

        $settings = NameComSettings::forTenant($tenantId);
        return round((float) $usd * (float) $settings->usd_rate, 2);
    }

    private function holdDomain(Domain $domain, string $reason, ?float $amount = null): void
    {
        $meta = $domain->meta ?? [];
        $meta['wallet_hold'] = ['reason' => $reason, 'amount_needed' => $amount, 'at' => now()->toIso8601String()];
        $domain->update(['meta' => $meta]);
    }

    private function clearDomainHold(Domain $domain): void
    {
        if (!empty($domain->meta['wallet_hold'] ?? null)) {
            $meta = $domain->meta;
            unset($meta['wallet_hold']);
            $domain->update(['meta' => $meta]);
        }
    }

    private function notifyTenant(Tenant $tenant, string $label, string $reason, ?float $amountNeeded = null, ?float $currentBalance = null): void
    {
        try {
            $admins = User::withoutGlobalScopes()->where('tenant_id', $tenant->id)->where('role', 'admin')->where('is_active', true)->get();
            if ($admins->isNotEmpty()) {
                Notification::send($admins, new TenantWalletHoldNotification($label, $reason, $amountNeeded, $currentBalance));
            }
        } catch (\Throwable $e) {
            report($e);
        }
    }

    // ─────────────────────────────── retry ───────────────────────────────

    /**
     * Called right after a successful topUp(): fulfil whatever was held for
     * this tenant, oldest first, only as far as the refreshed balance covers.
     * Re-dispatches the exact same jobs the observers would have dispatched
     * originally — no duplicate logic, no different code path.
     */
    public function retryHeld(Tenant $tenant): void
    {
        if (!$this->isGated($tenant)) {
            return;
        }

        $subs = ClientSubscription::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->whereNotNull('metadata->wallet_hold')
            ->orderBy('created_at')
            ->get();

        foreach ($subs as $sub) {
            if (!$this->allowHostingProvision($sub)) {
                continue; // still short — stop trying this one, but keep going to check others below is fine (independent balances)
            }
            $product = $sub->productService()->withoutGlobalScopes()->first();
            if ($product && $product->provisioning_type === 'whm_cpanel' && $product->auto_provision && !$sub->hostingAccount) {
                \App\Jobs\Hosting\ProvisionHostingAccount::dispatch($sub);
            }
        }

        $domains = Domain::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->whereNotNull('meta->wallet_hold')
            ->orderBy('created_at')
            ->get();

        foreach ($domains as $domain) {
            if (!$this->allowDomainFulfillment($domain)) {
                continue;
            }
            match ($domain->meta['pending_action'] ?? null) {
                'register' => \App\Jobs\Domains\RegisterDomainJob::dispatch($domain),
                'transfer' => \App\Jobs\Domains\TransferDomainJob::dispatch($domain),
                'renew'    => \App\Jobs\Domains\RenewDomainJob::dispatch($domain),
                default    => null,
            };
        }
    }
}
