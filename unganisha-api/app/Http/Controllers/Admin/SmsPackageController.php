<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\SmsPackage;
use Illuminate\Http\Request;

class SmsPackageController extends Controller
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
            'data' => SmsPackage::ordered()->get(),
        ]);
    }

    public function store(Request $request)
    {
        $this->authorize();

        $validated = $request->validate([
            'name' => 'required|string|max:100',
            'price_per_sms' => 'required|numeric|min:0.01',
            'min_quantity' => 'required|integer|min:1',
            'max_quantity' => 'nullable|integer|min:1',
            'is_active' => 'boolean',
            'sort_order' => 'integer',
        ]);

        $package = SmsPackage::create($validated);

        return response()->json(['data' => $package], 201);
    }

    public function update(Request $request, SmsPackage $smsPackage)
    {
        $this->authorize();

        $validated = $request->validate([
            'name' => 'required|string|max:100',
            'price_per_sms' => 'required|numeric|min:0.01',
            'min_quantity' => 'required|integer|min:1',
            'max_quantity' => 'nullable|integer|min:1',
            'is_active' => 'boolean',
            'sort_order' => 'integer',
        ]);

        $smsPackage->update($validated);

        return response()->json(['data' => $smsPackage]);
    }

    public function destroy(SmsPackage $smsPackage)
    {
        $this->authorize();

        $smsPackage->delete();

        return response()->json(['message' => 'Package deleted.']);
    }
}
