<?php

namespace App\Http\Controllers;

use App\Models\ProductService;
use App\Models\Tenant;
use Illuminate\Http\Request;

/**
 * Public hosting/email/cloud-server catalog (unauthenticated) for the
 * storefront landing page — same purpose as PublicDomainController's search:
 * let a visitor see real plans and prices before signing in. Presentation
 * fields only (ProductService.cost_price is $hidden on the model already).
 *
 * Resolved from the real Host exactly like PublicBrandingController/
 * PublicDomainController, so a white-label domain sees only its own tenant's
 * catalog — never another tenant's.
 */
class PublicCatalogController extends Controller
{
    public function show(Request $request)
    {
        $tenantId = $this->storefrontTenantId($request);
        if (!$tenantId) {
            return response()->json(['hosting' => [], 'email' => [], 'linode' => []]);
        }

        $plan = fn (ProductService $p) => [
            'name'          => $p->name,
            'price'         => (float) $p->price,
            'billing_cycle' => $p->billing_cycle,
            // "Disk Space: 10 GB · Bandwidth: Unlimited · ..." when staff have
            // filled it in (often auto-pulled from the real WHM package specs
            // — see ProductServiceForm's packageSpecsText()); null otherwise,
            // never invented here.
            'description'   => $p->description,
        ];

        $hosting = ProductService::withoutGlobalScopes()->where('tenant_id', $tenantId)
            ->where('type', 'product')->where('provisioning_type', 'whm_cpanel')->where('is_active', true)
            ->orderBy('price')->get()->map($plan)->values();

        $email = ProductService::withoutGlobalScopes()->where('tenant_id', $tenantId)
            ->where('type', 'product')->where('category', 'like', '%mail%')->where('is_active', true)
            ->orderBy('price')->get()->map($plan)->values();

        $linode = ProductService::withoutGlobalScopes()->where('tenant_id', $tenantId)
            ->where('provisioning_type', 'linode')->where('is_active', true)
            ->orderBy('price')->get()->map($plan)->values();

        return response()->json(['hosting' => $hosting, 'email' => $email, 'linode' => $linode]);
    }

    private function storefrontTenantId(Request $request): ?string
    {
        $host = strtolower(trim($request->getHost()));

        $tenant = $host
            ? Tenant::where('custom_domain', $host)->where('is_active', true)->first()
            : null;

        return $tenant?->id ?? config('portal.storefront_tenant_id');
    }
}
