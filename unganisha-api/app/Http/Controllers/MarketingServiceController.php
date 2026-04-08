<?php

namespace App\Http\Controllers;

use App\Models\MarketingService;
use Illuminate\Http\Request;

class MarketingServiceController extends Controller
{
    public function index()
    {
        return response()->json(MarketingService::orderBy('sort_order')->orderBy('name')->get());
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'name' => 'required|string|max:100',
        ]);

        // Check uniqueness manually since unique rule doesn't know about tenant scope easily
        $exists = MarketingService::where('name', $data['name'])->exists();
        if ($exists) {
            return response()->json(['message' => 'Service already exists.'], 422);
        }

        $maxOrder = MarketingService::max('sort_order') ?? -1;
        $service = MarketingService::create([
            'name'       => $data['name'],
            'sort_order' => $maxOrder + 1,
        ]);

        return response()->json($service, 201);
    }

    public function update(Request $request, MarketingService $marketingService)
    {
        $data = $request->validate([
            'name' => 'required|string|max:100',
        ]);

        $exists = MarketingService::where('name', $data['name'])
            ->where('id', '!=', $marketingService->id)
            ->exists();
        if ($exists) {
            return response()->json(['message' => 'Service already exists.'], 422);
        }

        $marketingService->update($data);

        return response()->json($marketingService);
    }

    public function destroy(MarketingService $marketingService)
    {
        $marketingService->delete();
        return response()->json(null, 204);
    }

    public function reorder(Request $request)
    {
        $data = $request->validate([
            'ids'   => 'required|array',
            'ids.*' => 'uuid',
        ]);

        foreach ($data['ids'] as $order => $id) {
            MarketingService::where('id', $id)->update(['sort_order' => $order]);
        }

        return response()->json(['ok' => true]);
    }
}
