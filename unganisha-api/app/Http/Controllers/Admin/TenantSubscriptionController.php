<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\SubscriptionPlan;
use App\Models\Tenant;
use App\Models\TenantSubscription;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class TenantSubscriptionController extends Controller
{
    private function authorize(): void
    {
        if (!auth()->user()->isSuperAdmin()) {
            abort(403, 'Unauthorized');
        }
    }

    public function index(Tenant $tenant): JsonResponse
    {
        $this->authorize();

        $subscriptions = TenantSubscription::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->with('plan', 'user')
            ->latest()
            ->paginate(20);

        return response()->json($subscriptions);
    }

    public function extend(Request $request, Tenant $tenant): JsonResponse
    {
        $this->authorize();

        $request->validate([
            'plan_id' => 'required|uuid|exists:subscription_plans,id',
            'days' => 'required|integer|min:1|max:365',
        ]);

        $plan = SubscriptionPlan::findOrFail($request->plan_id);

        // Find existing active subscription to extend from
        $existingActive = TenantSubscription::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->where('status', 'active')
            ->where('ends_at', '>', now())
            ->orderByDesc('ends_at')
            ->first();

        $startsAt = $existingActive ? $existingActive->ends_at : now();
        $endsAt = $startsAt->copy()->addDays($request->days);

        $subscription = TenantSubscription::withoutGlobalScopes()->create([
            'tenant_id' => $tenant->id,
            'subscription_plan_id' => $plan->id,
            'user_id' => auth()->id(),
            'status' => 'active',
            'starts_at' => $startsAt,
            'ends_at' => $endsAt,
            'amount_paid' => 0,
            'paid_at' => now(),
            'payment_status_description' => 'Admin-granted extension',
        ]);

        $subscription->load('plan');

        return response()->json([
            'message' => "Subscription extended by {$request->days} days.",
            'data' => $subscription,
        ], 201);
    }
}
