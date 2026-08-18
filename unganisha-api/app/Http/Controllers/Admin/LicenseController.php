<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\License;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class LicenseController extends Controller
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

        $query = License::withCount('activations')->latest();

        if ($search = $request->input('search')) {
            $query->where(function ($q) use ($search) {
                $q->where('customer_name', 'like', "%{$search}%")
                  ->orWhere('customer_email', 'like', "%{$search}%")
                  ->orWhere('license_key', 'like', "%{$search}%")
                  ->orWhere('domain', 'like', "%{$search}%");
            });
        }

        return response()->json($query->paginate($request->input('per_page', 20)));
    }

    public function store(Request $request)
    {
        $this->authorize();

        $validated = $request->validate([
            'customer_name' => 'required|string|max:255',
            'customer_email' => 'required|email|max:255',
            'product' => 'nullable|string|max:100',
            'starts_at' => 'required|date',
            'billing_period' => ['required', Rule::in(['perpetual', 'monthly', 'quarterly', 'semi_annual', 'annual'])],
            'notes' => 'nullable|string|max:2000',
        ]);
        $validated['license_key'] = License::generateKey();
        $validated['status'] = 'active';
        $validated['expires_at'] = License::calculateExpiry($validated['starts_at'], $validated['billing_period']);

        $license = License::create($validated);

        return response()->json(['data' => $license], 201);
    }

    /**
     * Renewal path: pass starts_at + billing_period to recalculate
     * expires_at (e.g. renewing for another period from today). Omit both
     * to leave expires_at untouched — e.g. just editing customer details
     * or status.
     */
    public function update(Request $request, License $license)
    {
        $this->authorize();

        $validated = $request->validate([
            'customer_name' => 'required|string|max:255',
            'customer_email' => 'required|email|max:255',
            'status' => ['required', Rule::in(['active', 'suspended', 'expired'])],
            'starts_at' => 'nullable|date',
            'billing_period' => ['nullable', Rule::in(['perpetual', 'monthly', 'quarterly', 'semi_annual', 'annual'])],
            'notes' => 'nullable|string|max:2000',
        ]);

        if (!empty($validated['starts_at']) && !empty($validated['billing_period'])) {
            $validated['expires_at'] = License::calculateExpiry($validated['starts_at'], $validated['billing_period']);
        }

        $license->update($validated);

        return response()->json(['data' => $license]);
    }

    /** Clears the bound domain so the license can be re-activated on a different install. */
    public function unbindDomain(License $license)
    {
        $this->authorize();

        $license->update(['domain' => null]);
        $license->activations()->delete();

        return response()->json(['data' => $license]);
    }

    public function destroy(License $license)
    {
        $this->authorize();

        $license->delete();

        return response()->json(['message' => 'License deleted.']);
    }
}
