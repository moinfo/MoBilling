<?php

namespace App\Http\Controllers;

use App\Models\DomainTld;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class DomainTldController extends Controller
{
    public function index()
    {
        $tenantId = auth()->user()->tenant_id;

        // Tenant rows override platform (NULL tenant) rows for the same TLD.
        $rows = DomainTld::where(fn ($q) => $q->where('tenant_id', $tenantId)->orWhereNull('tenant_id'))
            ->orderBy('tld')->orderByRaw('tenant_id IS NULL')
            ->get()
            ->unique('tld')
            ->values()
            ->map(fn ($t) => [
                'id'             => $t->id,
                'tld'            => $t->tld,
                'register_price' => (float) $t->register_price,
                'renew_price'    => (float) $t->renew_price,
                'transfer_price' => (float) $t->transfer_price,
                'years_min'      => $t->years_min,
                'years_max'      => $t->years_max,
                'is_active'      => $t->is_active,
                'is_platform'    => is_null($t->tenant_id),
            ]);

        return response()->json(['data' => $rows]);
    }

    public function store(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'tld'            => ['required', 'string', 'max:30', 'regex:/^[a-z.]+$/',
                                 Rule::unique('domain_tlds')->where('tenant_id', $tenantId)],
            'register_price' => 'required|numeric|min:0',
            'renew_price'    => 'required|numeric|min:0',
            'transfer_price' => 'nullable|numeric|min:0',
            'years_min'      => 'nullable|integer|min:1|max:10',
            'years_max'      => 'nullable|integer|min:1|max:10',
            'is_active'      => 'boolean',
        ]);

        $tld = DomainTld::create($data + ['tenant_id' => $tenantId]);

        return response()->json(['data' => $tld], 201);
    }

    public function update(Request $request, DomainTld $domainTld)
    {
        abort_unless($domainTld->tenant_id === auth()->user()->tenant_id, 403);

        $data = $request->validate([
            'register_price' => 'sometimes|numeric|min:0',
            'renew_price'    => 'sometimes|numeric|min:0',
            'transfer_price' => 'nullable|numeric|min:0',
            'years_min'      => 'nullable|integer|min:1|max:10',
            'years_max'      => 'nullable|integer|min:1|max:10',
            'is_active'      => 'boolean',
        ]);

        $domainTld->update($data);

        return response()->json(['data' => $domainTld->fresh()]);
    }

    public function destroy(DomainTld $domainTld)
    {
        abort_unless($domainTld->tenant_id === auth()->user()->tenant_id, 403);
        $domainTld->delete();
        return response()->json(null, 204);
    }
}
