<?php

namespace App\Http\Controllers;

use App\Models\Tenant;
use Illuminate\Http\Request;

/**
 * White-label branding lookup (public, unauthenticated).
 *
 * The SPA calls this on boot; when the visiting hostname matches a tenant's
 * custom_domain, the portal renders under that tenant's name and logo.
 * Only safe, presentation-level fields are ever returned.
 */
class PublicBrandingController extends Controller
{
    public function show(Request $request)
    {
        $host = strtolower(trim($request->query('host', $request->getHost())));

        $tenant = $host
            ? Tenant::where('custom_domain', $host)->where('is_active', true)->first()
            : null;

        if (!$tenant) {
            return response()->json(['branded' => false]);
        }

        return response()->json([
            'branded'  => true,
            'name'     => $tenant->name,
            'logo_url' => $tenant->logo_url,
            'website'  => $tenant->website,
            'email'    => $tenant->email,
            'phone'    => $tenant->phone,
        ]);
    }
}
