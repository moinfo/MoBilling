<?php

namespace App\Http\Controllers;

use App\Http\Requests\StoreWifiPlanRequest;
use App\Http\Resources\WifiPlanResource;
use App\Models\WifiPlan;
use Illuminate\Http\Request;

class WifiPlanController extends Controller
{
    public function index(Request $request)
    {
        $query = WifiPlan::with('router:id,name');

        if ($request->filled('mikrotik_router_id')) {
            $query->where('mikrotik_router_id', $request->mikrotik_router_id);
        }

        return WifiPlanResource::collection(
            $query->orderBy('price')->paginate($request->per_page ?? 50)
        );
    }

    public function store(StoreWifiPlanRequest $request)
    {
        $plan = WifiPlan::create($request->validated());
        return new WifiPlanResource($plan->load('router:id,name'));
    }

    public function show(WifiPlan $wifi_plan)
    {
        return new WifiPlanResource($wifi_plan->load('router:id,name'));
    }

    public function update(StoreWifiPlanRequest $request, WifiPlan $wifi_plan)
    {
        $wifi_plan->update($request->validated());
        return new WifiPlanResource($wifi_plan->load('router:id,name'));
    }

    public function destroy(WifiPlan $wifi_plan)
    {
        $wifi_plan->delete();
        return response()->json(['message' => 'Plan deleted']);
    }
}
