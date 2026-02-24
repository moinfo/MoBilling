<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\SmsPurchase;
use Illuminate\Http\Request;

class SmsPurchaseController extends Controller
{
    private function authorize(): void
    {
        if (!auth()->user()->isSuperAdmin()) {
            abort(403, 'Unauthorized');
        }
    }

    public function index(Request $request)
    {
        $this->authorize();

        $query = SmsPurchase::withoutGlobalScopes()
            ->with(['user:id,name,email', 'tenant:id,name'])
            ->latest();

        if ($request->has('status') && in_array($request->status, ['pending', 'completed', 'failed'])) {
            $query->where('status', $request->status);
        }

        if ($request->has('tenant_id')) {
            $query->where('tenant_id', $request->tenant_id);
        }

        return response()->json($query->paginate(20));
    }
}
