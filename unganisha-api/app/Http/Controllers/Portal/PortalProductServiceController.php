<?php

namespace App\Http\Controllers\Portal;

use App\Http\Controllers\Controller;
use App\Models\ProductService;
use Illuminate\Http\Request;

class PortalProductServiceController extends Controller
{
    public function index(Request $request)
    {
        $tenantId = $request->user()->tenant_id;

        $query = ProductService::withoutGlobalScopes()
            ->where('tenant_id', $tenantId)
            ->where('is_active', true)
            // Linode Server products are billed manually by staff — never self-orderable.
            ->where(fn ($q) => $q->whereNull('provisioning_type')->orWhere('provisioning_type', '!=', 'linode'))
            ->orderBy('type')
            ->orderBy('name');

        if ($request->filled('type')) {
            $query->where('type', $request->type);
        }

        if ($request->filled('search')) {
            $query->where('name', 'like', "%{$request->search}%");
        }

        return response()->json(['data' => $query->get()]);
    }
}
