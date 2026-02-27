<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\SubscriptionPlan;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class SubscriptionPlanController extends Controller
{
    private function authorize(): void
    {
        if (!auth()->user()->isSuperAdmin()) {
            abort(403, 'Unauthorized');
        }
    }

    public function index(): JsonResponse
    {
        $this->authorize();

        $plans = SubscriptionPlan::ordered()
            ->withCount('permissions')
            ->with('permissions:id')
            ->get();

        return response()->json([
            'data' => $plans,
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorize();

        $validated = $request->validate([
            'name' => 'required|string|max:100',
            'slug' => 'required|string|max:100|unique:subscription_plans,slug',
            'description' => 'nullable|string|max:500',
            'price' => 'required|numeric|min:0',
            'billing_cycle_days' => 'integer|min:1',
            'features' => 'nullable|array',
            'is_active' => 'boolean',
            'sort_order' => 'integer',
            'permission_ids' => 'nullable|array',
            'permission_ids.*' => 'uuid|exists:permissions,id',
        ]);

        $permissionIds = $validated['permission_ids'] ?? [];
        unset($validated['permission_ids']);

        $plan = SubscriptionPlan::create($validated);
        $plan->permissions()->sync($permissionIds);
        $plan->loadCount('permissions')->load('permissions:id');

        return response()->json(['data' => $plan], 201);
    }

    public function update(Request $request, SubscriptionPlan $subscriptionPlan): JsonResponse
    {
        $this->authorize();

        $validated = $request->validate([
            'name' => 'required|string|max:100',
            'slug' => 'required|string|max:100|unique:subscription_plans,slug,' . $subscriptionPlan->id,
            'description' => 'nullable|string|max:500',
            'price' => 'required|numeric|min:0',
            'billing_cycle_days' => 'integer|min:1',
            'features' => 'nullable|array',
            'is_active' => 'boolean',
            'sort_order' => 'integer',
            'permission_ids' => 'nullable|array',
            'permission_ids.*' => 'uuid|exists:permissions,id',
        ]);

        $permissionIds = $validated['permission_ids'] ?? [];
        unset($validated['permission_ids']);

        $subscriptionPlan->update($validated);
        $subscriptionPlan->permissions()->sync($permissionIds);
        $subscriptionPlan->loadCount('permissions')->load('permissions:id');

        return response()->json(['data' => $subscriptionPlan]);
    }

    public function destroy(SubscriptionPlan $subscriptionPlan): JsonResponse
    {
        $this->authorize();

        $subscriptionPlan->delete();

        return response()->json(['message' => 'Subscription plan deleted.']);
    }
}
