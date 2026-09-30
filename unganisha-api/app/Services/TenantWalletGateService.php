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

    /**
     * Writes via a plain query-builder update (bypassing Eloquent's save()/model events) and
     * only then syncs the in-memory attribute — calling $sub->update() here would re-fire
     * ClientSubscriptionObserver::updated() while the OUTER save() that got us here hasn't
     * finished (Eloquent only syncs $original in finishSave(), after 'updated' fires), so
     * wasChanged('status') would still read true on the nested call and recurse forever.
     */
    private function holdHosting(ClientSubscription $sub, string $reason, ?float $amount = null): void
    {
        $meta = $sub->metadata ?? [];
        $meta['wallet_hold'] = ['reason' => $reason, 'amount_needed' => $amount, 'at' => now()->toIso8601String()];
        ClientSubscription::withoutGlobalScopes()->whereKey($sub->id)->update(['metadata' => $meta]);
        $sub->metadata = $meta;
    }

    private function clearHostingHold(ClientSubscription $sub): void
    {
        if (!empty($sub->metadata['wallet_hold'] ?? null)) {
            $meta = $sub->metadata;
            unset($meta['wallet_hold']);
            ClientSubscription::withoutGlobalScopes()->whereKey($sub->id)->update(['metadata' => $meta]);
            $sub->metadata = $meta;
        }
    }

    // ─────────────────────────────── domains ───────────────────────────────

    /**
     * True = the caller may proceed with Register/Transfer/RenewDomainJob::dispatch($domain)
     * (or, for the Name.com manual-queue path, NameComRegistrationService::onOrderPaid())
     * exactly as before. $action/$years default to reading $domain->meta, but DocumentObserver's
     * Name.com branch strips pending_action/pending_years from meta before this can run, so it
     * passes the pre-strip values explicitly instead.
     */
    public function allowDomainFulfillment(Domain $domain, ?string $action = null, ?int $years = null): bool
    {
        $tenant = Tenant::withoutGlobalScopes()->find($domain->tenant_id);
        if (!$tenant || !$this->isGated($tenant)) {
            return true;
        }

        if ($this->wallet->alreadyDebited(Domain::class, $domain->id)) {
            $this->clearDomainHold($domain);
            return true;
        }

        $action ??= $domain->meta['pending_action'] ?? null;
        $years = max(1, (int) ($years ?? $domain->meta['pending_years'] ?? 1));
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
     * null when no real cost source exists.
     *
     * Name.com TLDs: real usd cost fields (usd_register/usd_renew) converted
     * at the tenant's own Name.com FX rate.
     *
     * FRED (.tz) TLDs: no usd_* field exists for these (Name.com's API never
     * prices them), but this codebase already has an established wholesale
     * field for exactly this registrar — domain_tlds.reseller_price, the
     * same number PortalResellerController's own domain-reseller feature
     * already charges a client-level domain reseller, already in TZS
     * (no FX conversion needed). Only used when set (nullable) — a FRED TLD
     * with no reseller_price configured still returns null and holds,
     * exactly as before; nothing here ever guesses a number.
     */
    private function domainCostBasis(string $tenantId, string $domainName, ?string $action): ?float
    {
        $tld = strtolower(explode('.', $domainName, 2)[1] ?? '');

        $ncRow = DomainTld::where('tenant_id', $tenantId)->where('tld', $tld)->where('registrar', 'namecom')->first()
            ?? DomainTld::whereNull('tenant_id')->where('tld', $tld)->where('registrar', 'namecom')->first();

        if ($ncRow) {
            $usd = $action === 'renew' ? $ncRow->usd_renew : $ncRow->usd_register;
            if ($usd !== null) {
                $settings = NameComSettings::forTenant($tenantId);
                return round((float) $usd * (float) $settings->usd_rate, 2);
            }
        }

        $fredRow = DomainTld::where('tenant_id', $tenantId)->where('tld', $tld)->where('registrar', 'fred')->first()
            ?? DomainTld::whereNull('tenant_id')->where('tld', $tld)->where('registrar', 'fred')->first();

        if ($fredRow && $fredRow->reseller_price !== null) {
            return round((float) $fredRow->reseller_price, 2);
        }

        return null; // no wholesale-cost source configured for this TLD — never guess
    }

    // Same plain query-builder-update pattern as holdHosting()/clearHostingHold() above — no
    // Domain observer exists today, but this keeps the two symmetric and safe against one
    // being added later while this is called from within another model's 'updated' event.
    private function holdDomain(Domain $domain, string $reason, ?float $amount = null): void
    {
        $meta = $domain->meta ?? [];
        $meta['wallet_hold'] = ['reason' => $reason, 'amount_needed' => $amount, 'at' => now()->toIso8601String()];
        Domain::withoutGlobalScopes()->whereKey($domain->id)->update(['meta' => $meta]);
        $domain->meta = $meta;
    }

    private function clearDomainHold(Domain $domain): void
    {
        if (!empty($domain->meta['wallet_hold'] ?? null)) {
            $meta = $domain->meta;
            unset($meta['wallet_hold']);
            Domain::withoutGlobalScopes()->whereKey($domain->id)->update(['meta' => $meta]);
            $domain->meta = $meta;
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
            // Name.com domains take the "unmanaged" manual-queue path in DocumentObserver, which
            // strips pending_action from meta before this hold could even be set — so a held one
            // is only ever recognisable by unmanaged + awaiting_manual_registration + registrar.
            $isNameComQueued = ($domain->meta['unmanaged'] ?? false)
                && ($domain->meta['awaiting_manual_registration'] ?? false)
                && ($domain->meta['registrar'] ?? null) === 'namecom';

            if ($isNameComQueued) {
                if ($this->allowDomainFulfillment($domain, 'register', 1)) {
                    \App\Services\Registrar\NameComRegistrationService::onOrderPaid($domain->fresh());
                }
                continue;
            }

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
