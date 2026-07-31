<?php

namespace App\Http\Controllers;

use App\Exceptions\RegistrarApiException;
use App\Models\DomainTld;
use App\Models\Tenant;
use App\Services\Registrar\DomainRegistrarManager;
use Illuminate\Http\Request;

/**
 * Public domain availability search (unauthenticated).
 *
 * The moinfo.co.tz search box calls this so visitors can check a name and see
 * the price before being asked to create an account — signing in is only
 * required to actually place the order, which still goes through the
 * authenticated portal endpoints.
 *
 * Deliberately narrow: it answers "is this name free and what does it cost",
 * nothing else. No WHOIS, no registrant details, no catalog.
 */
class PublicDomainController extends Controller
{
    public function __construct(private DomainRegistrarManager $registrar)
    {
    }

    public function check(Request $request)
    {
        $data = $request->validate([
            'name' => 'required|string|max:255|regex:/^[a-z0-9][a-z0-9.-]+\.[a-z.]{2,}$/i',
        ]);
        $name = strtolower(trim($data['name']));

        $tenantId = $this->storefrontTenantId($request);
        if (!$tenantId) {
            return response()->json([
                'message' => 'Domain search is unavailable right now — please contact us.',
            ], 503);
        }

        // Reject an unsupported TLD before spending a registry call on it.
        $tld = strtolower(explode('.', $name, 2)[1] ?? '');
        $pricing = DomainTld::priceFor($tenantId, $tld);
        if (!$pricing) {
            return response()->json([
                'name'      => $name,
                'offered'   => false,
                'available' => null,
                'message'   => "We don't currently offer .{$tld} domains.",
            ]);
        }

        try {
            $result = $this->registrar->driverFor($tenantId)->check($name);
        } catch (RegistrarApiException $e) {
            report($e);

            return response()->json([
                'message' => 'Could not check that domain right now — please try again.',
            ], 503);
        }

        return response()->json([
            'name'      => $name,
            'offered'   => true,
            'available' => (bool) $result['available'],
            'pricing'   => [
                'tld'            => $pricing->tld,
                'register_price' => (float) $pricing->register_price,
                'transfer_price' => (float) $pricing->transfer_price,
                'years_min'      => $pricing->years_min,
                'years_max'      => $pricing->years_max,
            ],
        ]);
    }

    /**
     * Whose pricing and registrar account answer this search.
     *
     * Resolved from the real Host first so a white-label site checks against
     * its own tenant, exactly as PublicBrandingController does — and for the
     * same reason, the host is never taken from a query parameter, so this
     * cannot be used to probe another tenant's configuration.
     */
    private function storefrontTenantId(Request $request): ?string
    {
        $host = strtolower(trim($request->getHost()));

        $tenant = $host
            ? Tenant::where('custom_domain', $host)->where('is_active', true)->first()
            : null;

        return $tenant?->id ?? config('portal.storefront_tenant_id');
    }
}