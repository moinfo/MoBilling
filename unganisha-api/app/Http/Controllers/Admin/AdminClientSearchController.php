<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Client;
use Illuminate\Http\Request;

/**
 * Cross-tenant client search for super-admin screens (e.g. the "Promote from
 * Client" picker on Admin > Tenants) — the regular GET /clients is scoped to
 * the caller's own tenant, which is useless for a super admin browsing every
 * tenant's clients.
 */
class AdminClientSearchController extends Controller
{
    public function index(Request $request)
    {
        if (!auth()->user()->isSuperAdmin()) {
            abort(403, 'Unauthorized');
        }

        $search = $request->input('search', '');
        if (strlen($search) < 2) {
            return response()->json(['data' => []]);
        }

        $clients = Client::withoutGlobalScopes()
            ->with('tenant:id,name,currency')
            ->where(function ($q) use ($search) {
                $q->where('name', 'like', "%{$search}%")
                    ->orWhere('email', 'like', "%{$search}%")
                    ->orWhere('phone', 'like', "%{$search}%")
                    ->orWhere('tax_id', 'like', "%{$search}%");
            })
            ->limit(20)
            ->get(['id', 'tenant_id', 'name', 'email', 'phone', 'tax_id', 'address']);

        return response()->json(['data' => $clients]);
    }
}
