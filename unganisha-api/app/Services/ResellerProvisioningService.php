<?php

namespace App\Services;

use App\Models\DomainTld;
use App\Models\LinodeAccount;
use App\Models\NameComAccount;
use App\Models\ProductService;
use App\Models\ResellerApplication;
use App\Models\Server;
use App\Models\Tenant;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Turns an APPROVED ResellerApplication into a real, independent Tenant:
 * its own admin login, its own product catalog priced at Moinfotech's
 * current retail prices (the reseller edits them from there), fulfilled on
 * the SAME shared infrastructure Moinfotech already uses. Everything real
 * (WHM, Linode, registrar, Pesapal, email/SMS/WhatsApp) stays untouched —
 * this only creates local rows: a new Tenant/User/Role/Permission set (via
 * the existing TenantProvisioningService, reused as-is), and per selected
 * category, a LOCAL COPY of the relevant infra credential row(s) (re-saved
 * through each model's own encrypted cast so they round-trip correctly) and
 * a curated set of ProductService/DomainTld rows.
 *
 * IMPORTANT deliberate deviations from a literal "duplicate every infra
 * type" reading, backed by how this codebase's registrar resolution
 * actually works (see report):
 *  - RegistrarAccount (FRED .tz) is NOT duplicated. It has a NULL
 *    tenant_id (a genuinely platform-wide shared row) and
 *    DomainRegistrarManager::accountFor() already falls back to it for any
 *    tenant with no row of its own — duplicating it would take it OUT of
 *    that shared-fallback status for no benefit.
 *  - NameComAccount (BelongsToTenant, no such fallback) IS duplicated —
 *    the reseller's default Name.com account, same real credentials.
 */
class ResellerProvisioningService
{
    public function __construct(private TenantProvisioningService $tenantProvisioning) {}

    /**
     * A dry-run summary of exactly what provision() would create — infra
     * rows to duplicate, products to create with their retail/cost prices,
     * and any cost-price gaps staff should know about before committing.
     */
    public function preview(ResellerApplication $application): array
    {
        $sourceTenantId = $application->tenant_id;
        $categories = $application->categories;

        $infra = [];
        $products = [];
        $warnings = [];

        if (in_array('domain', $categories, true)) {
            $namecom = NameComAccount::defaultFor($sourceTenantId);
            $infra[] = ['category' => 'domain', 'label' => $namecom ? "Name.com account — {$namecom->displayLabel()} (Shared — same as Moinfotech)" : 'No Name.com account found — .tz (FRED) still sells via the shared platform registrar'];

            $tldRows = DomainTld::where('tenant_id', $sourceTenantId)->get();
            foreach ($tldRows as $row) {
                $hasCost = ($row->registrar === 'namecom' && $row->usd_register !== null)
                    || ($row->registrar === 'fred' && $row->reseller_price !== null);
                if (!$hasCost) {
                    $warnings[] = ".{$row->tld} ({$row->registrar}) has no wholesale-cost source — reseller sales of it will be held until the owner sets one up manually.";
                }
            }
            $products[] = ['category' => 'domain', 'name' => count($tldRows) . ' TLD price(s) copied from Moinfotech', 'retail_price' => null, 'cost_price' => null, 'cost_flagged' => false];
        }

        if (in_array('hosting', $categories, true)) {
            $server = Server::withoutGlobalScopes()->where('tenant_id', $sourceTenantId)->where('type', 'whm_cpanel')->where('is_active', true)->first();
            $infra[] = ['category' => 'hosting', 'label' => $server ? "Server — {$server->name} (Shared — same as Moinfotech)" : 'No active WHM server found on Moinfotech\'s own tenant'];

            foreach ($this->hostingProducts($sourceTenantId) as $p) {
                $products[] = ['category' => 'hosting', 'name' => $p->name, 'retail_price' => (float) $p->price, 'cost_price' => null, 'cost_flagged' => true];
                $warnings[] = "\"{$p->name}\" has no wholesale-cost source — set product_services.cost_price manually before trusting the wallet gate for it.";
            }
        }

        if (in_array('email', $categories, true)) {
            foreach ($this->emailProducts($sourceTenantId) as $p) {
                $products[] = ['category' => 'email', 'name' => $p->name, 'retail_price' => (float) $p->price, 'cost_price' => null, 'cost_flagged' => true];
            }
        }

        if (in_array('linode', $categories, true)) {
            $linode = LinodeAccount::withoutGlobalScopes()->where('tenant_id', $sourceTenantId)->first();
            $infra[] = ['category' => 'linode', 'label' => $linode ? "Linode account — {$linode->label} (Shared — same as Moinfotech)" : 'No Linode account found on Moinfotech\'s own tenant'];

            foreach ($this->linodeProducts($sourceTenantId) as $p) {
                $products[] = ['category' => 'linode', 'name' => $p->name, 'retail_price' => (float) $p->price, 'cost_price' => null, 'cost_flagged' => true];
            }
            $warnings[] = 'Linode servers are billed manually in this app (no auto-provisioning) — the wallet gate does not apply to them.';
        }

        return ['categories' => $categories, 'infra' => $infra, 'products' => $products, 'warnings' => array_values(array_unique($warnings))];
    }

    private function hostingProducts(string $tenantId)
    {
        return ProductService::withoutGlobalScopes()->where('tenant_id', $tenantId)
            ->where('type', 'product')->where('provisioning_type', 'whm_cpanel')->where('is_active', true)->get();
    }

    private function emailProducts(string $tenantId)
    {
        return ProductService::withoutGlobalScopes()->where('tenant_id', $tenantId)
            ->where('type', 'product')->where('category', 'like', '%mail%')->where('is_active', true)->get();
    }

    private function linodeProducts(string $tenantId)
    {
        return ProductService::withoutGlobalScopes()->where('tenant_id', $tenantId)
            ->where('provisioning_type', 'linode')->where('is_active', true)->get();
    }

    /**
     * @return array{0: Tenant, 1: User} [$tenant, $adminUser] — $adminUser's
     *   password is a random secret never returned or logged; the reseller
     *   sets their own via the existing "Forgot password" flow.
     */
    public function provision(ResellerApplication $application, User $actingStaff): array
    {
        if ($application->status !== 'approved') {
            throw new \RuntimeException('Only an approved application can be provisioned.');
        }
        if ($application->provisioned_tenant_id) {
            throw new \RuntimeException('This application has already been provisioned.');
        }

        $domain = strtolower($application->requested_domain);
        if (Tenant::withoutGlobalScopes()->whereRaw('LOWER(custom_domain) = ?', [$domain])->exists()) {
            throw new \RuntimeException('This domain has since been claimed by another tenant — cannot provision.');
        }

        $sourceTenantId = $application->tenant_id;
        $sourceTenant = Tenant::withoutGlobalScopes()->findOrFail($sourceTenantId);

        return DB::transaction(function () use ($application, $actingStaff, $domain, $sourceTenantId, $sourceTenant) {
            $originalTenantId = $actingStaff->tenant_id;

            try {
                [$tenant, $adminUser] = $this->tenantProvisioning->provision(
                    [
                        'name'            => $application->brand_name,
                        'email'           => $application->contact_email,
                        'phone'           => $application->contact_phone,
                        'currency'        => $sourceTenant->currency ?? 'TZS',
                        'custom_domain'   => $domain,
                        'trial_ends_at'   => now()->addDays(7),
                        'is_wallet_gated' => true,
                        'wallet_balance'  => 0,
                    ],
                    [
                        'name'     => $application->contact_name,
                        'email'    => $application->contact_email,
                        'password' => Str::password(40),
                        'phone'    => $application->contact_phone,
                    ],
                    'reseller',
                    function ($t) use ($actingStaff) {
                        $actingStaff->tenant_id = $t->id;
                    },
                );

                $categories = $application->categories;
                $serverIdMap = [];

                if (in_array('domain', $categories, true)) {
                    $this->duplicateDomainInfra($sourceTenantId, $tenant->id);
                }
                if (in_array('hosting', $categories, true)) {
                    $serverIdMap = $this->duplicateServer($sourceTenantId, $tenant->id);
                    $this->duplicateProducts($this->hostingProducts($sourceTenantId), $tenant->id, $serverIdMap);
                }
                if (in_array('email', $categories, true)) {
                    $this->duplicateProducts($this->emailProducts($sourceTenantId), $tenant->id, $serverIdMap);
                }
                if (in_array('linode', $categories, true)) {
                    $this->duplicateLinodeAccount($sourceTenantId, $tenant->id);
                    $this->duplicateProducts($this->linodeProducts($sourceTenantId), $tenant->id, $serverIdMap);
                }

                $application->update([
                    'status'                => 'provisioned',
                    'provisioned_tenant_id' => $tenant->id,
                    'decided_by'            => $actingStaff->id,
                    'decided_at'            => now(),
                ]);

                return [$tenant, $adminUser];
            } finally {
                $actingStaff->tenant_id = $originalTenantId;
            }
        });
    }

    /** NameComAccount (default) + the source tenant's own DomainTld price overrides — re-saved via Eloquent so the token re-encrypts correctly. */
    private function duplicateDomainInfra(string $sourceTenantId, string $newTenantId): void
    {
        $source = NameComAccount::defaultFor($sourceTenantId);
        if ($source) {
            NameComAccount::withoutGlobalScopes()->create([
                'tenant_id'   => $newTenantId,
                'label'       => trim(($source->label ?: $source->username) . ' (Shared — same as Moinfotech)'),
                'is_default'  => true,
                'username'    => $source->username,
                'token'       => $source->token, // decrypted on read via the cast, re-encrypted on save for the new row
                'token_hint'  => $source->token_hint,
                'is_sandbox'  => $source->is_sandbox,
                'status'      => $source->status,
            ]);
        }

        $tldRows = DomainTld::where('tenant_id', $sourceTenantId)->get();
        foreach ($tldRows as $row) {
            DomainTld::create([
                'tenant_id'        => $newTenantId,
                'tld'              => $row->tld,
                'registrar'        => $row->registrar,
                'register_price'   => $row->register_price,
                'renew_price'      => $row->renew_price,
                'transfer_price'   => $row->transfer_price,
                'years_min'        => $row->years_min,
                'years_max'        => $row->years_max,
                'is_active'        => $row->is_active,
                'is_unmanaged'     => $row->is_unmanaged,
                'is_popular'       => $row->is_popular,
                'sort_order'       => $row->sort_order,
                // Wholesale USD cost carried over as-is ($hidden only affects serialization,
                // not attribute access) so TenantWalletGateService can compute a cost basis
                // for this tenant immediately — FRED rows have none, exactly like the source.
                'usd_register'     => $row->usd_register,
                'usd_renew'        => $row->usd_renew,
                'usd_transfer'     => $row->usd_transfer,
                // FRED (.tz) TLDs have no usd_* cost — reseller_price is the established
                // wholesale-cost field for those (see PortalResellerController's own
                // domain-reseller feature and TenantWalletGateService::domainCostBasis()).
                'reseller_price'   => $row->reseller_price,
            ]);
        }
    }

    /** @return array<string,string> old Server id => new Server id */
    private function duplicateServer(string $sourceTenantId, string $newTenantId): array
    {
        $map = [];
        $servers = Server::withoutGlobalScopes()->where('tenant_id', $sourceTenantId)->where('is_active', true)->get();
        foreach ($servers as $source) {
            $new = Server::withoutGlobalScopes()->create([
                'tenant_id'   => $newTenantId,
                'name'        => $source->name . ' (Shared — same as Moinfotech)',
                'hostname'    => $source->hostname,
                'port'        => $source->port,
                'username'    => $source->username,
                'api_token'   => $source->api_token, // decrypted on read, re-encrypted on save
                'nameservers' => $source->nameservers,
                'type'        => $source->type,
                'is_active'   => true,
                'verify_ssl'  => $source->verify_ssl,
            ]);
            $map[$source->id] = $new->id;
        }
        return $map;
    }

    private function duplicateLinodeAccount(string $sourceTenantId, string $newTenantId): void
    {
        $source = LinodeAccount::withoutGlobalScopes()->where('tenant_id', $sourceTenantId)->first();
        if (!$source) {
            return;
        }
        LinodeAccount::withoutGlobalScopes()->create([
            'tenant_id'  => $newTenantId,
            'label'      => $source->label . ' (Shared — same as Moinfotech)',
            'token'      => $source->token, // decrypted on read, re-encrypted on save
            'token_hint' => $source->token_hint,
            'soa_email'  => $source->soa_email,
            'status'     => $source->status,
        ]);
    }

    /**
     * @param \Illuminate\Support\Collection<int,ProductService> $products
     * @param array<string,string> $serverIdMap old Server id => new Server id
     */
    private function duplicateProducts($products, string $newTenantId, array $serverIdMap): void
    {
        foreach ($products as $source) {
            ProductService::withoutGlobalScopes()->create([
                'tenant_id'             => $newTenantId,
                'type'                  => $source->type,
                'name'                  => $source->name,
                'description'           => $source->description,
                'price'                 => $source->price, // retail — reseller's own starting price, edit in Settings
                'cost_price'            => null,           // no real-cost source found automatically — see report
                'tax_percent'           => $source->tax_percent,
                'unit'                  => $source->unit,
                'category'              => $source->category,
                'billing_cycle'         => $source->billing_cycle,
                'invoice_day_of_month'  => $source->invoice_day_of_month,
                'is_active'             => $source->is_active,
                'provisioning_type'     => $source->provisioning_type,
                'server_id'             => $source->server_id ? ($serverIdMap[$source->server_id] ?? null) : null,
                'cpanel_package'        => $source->cpanel_package,
                'auto_provision'        => $source->auto_provision,
                'portal_visible'        => $source->portal_visible,
            ]);
        }
    }
}
