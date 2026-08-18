<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\LicensePlan;
use Illuminate\Http\Request;

class LicensePlanController extends Controller
{
    private function authorize(): void
    {
        if (!auth()->user()->isSuperAdmin()) {
            abort(403, 'Unauthorized');
        }
    }

    public function index()
    {
        $this->authorize();

        return response()->json(['data' => LicensePlan::orderBy('product')->get()]);
    }

    /** Rows are seeded (one per product) — this only edits prices/description, never creates/deletes. */
    public function update(Request $request, LicensePlan $licensePlan)
    {
        $this->authorize();

        $validated = $request->validate([
            'name' => 'required|string|max:255',
            'description' => 'nullable|string|max:1000',
            'monthly_price' => 'nullable|numeric|min:0',
            'quarterly_price' => 'nullable|numeric|min:0',
            'semi_annual_price' => 'nullable|numeric|min:0',
            'annual_price' => 'nullable|numeric|min:0',
            'perpetual_price' => 'nullable|numeric|min:0',
            'is_active' => 'boolean',
        ]);

        $licensePlan->update($validated);

        return response()->json(['data' => $licensePlan]);
    }
}
