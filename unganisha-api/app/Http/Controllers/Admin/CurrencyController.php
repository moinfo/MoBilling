<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Currency;
use Illuminate\Http\Request;

class CurrencyController extends Controller
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

        return response()->json([
            'data' => Currency::ordered()->get(),
        ]);
    }

    /**
     * Public endpoint — returns only active currencies for dropdowns.
     */
    public function active()
    {
        return response()->json([
            'data' => Currency::active()->ordered()->get(),
        ]);
    }

    public function store(Request $request)
    {
        $this->authorize();

        $validated = $request->validate([
            'code' => 'required|string|max:10|unique:currencies,code',
            'name' => 'required|string|max:100',
            'symbol' => 'nullable|string|max:10',
            'is_active' => 'boolean',
            'sort_order' => 'integer',
        ]);

        $currency = Currency::create($validated);

        return response()->json(['data' => $currency], 201);
    }

    public function update(Request $request, Currency $currency)
    {
        $this->authorize();

        $validated = $request->validate([
            'code' => 'required|string|max:10|unique:currencies,code,' . $currency->id,
            'name' => 'required|string|max:100',
            'symbol' => 'nullable|string|max:10',
            'is_active' => 'boolean',
            'sort_order' => 'integer',
        ]);

        $currency->update($validated);

        return response()->json(['data' => $currency]);
    }

    public function destroy(Currency $currency)
    {
        $this->authorize();

        $currency->delete();

        return response()->json(['message' => 'Currency deleted.']);
    }
}
