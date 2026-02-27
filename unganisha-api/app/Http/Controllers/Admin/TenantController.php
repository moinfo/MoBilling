<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Tenant;
use App\Models\TenantSubscription;
use App\Models\User;
use App\Services\SubscriptionService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rules\Password;

class TenantController extends Controller
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

        $query = Tenant::withCount(['users', 'allowedPermissions']);

        if ($search = $request->input('search')) {
            $query->where(function ($q) use ($search) {
                $q->where('name', 'like', "%{$search}%")
                  ->orWhere('email', 'like', "%{$search}%");
            });
        }

        $paginated = $query->latest()->paginate($request->input('per_page', 15));

        $paginated->getCollection()->transform(function ($tenant) {
            $tenant->subscription_status = $tenant->subscriptionStatus();
            $tenant->days_remaining = $tenant->daysRemaining();
            $tenant->expires_at = $this->getExpiresAt($tenant);
            return $tenant;
        });

        return response()->json($paginated);
    }

    public function store(Request $request)
    {
        $this->authorize();

        $request->validate([
            'name' => 'required|string|max:255',
            'email' => 'required|email|max:255',
            'phone' => 'nullable|string|max:20',
            'address' => 'nullable|string|max:500',
            'tax_id' => 'nullable|string|max:50',
            'currency' => 'nullable|string|max:10',
            'admin_name' => 'required|string|max:255',
            'admin_email' => 'required|email|unique:users,email',
            'admin_password' => ['required', Password::min(8)],
        ]);

        return DB::transaction(function () use ($request) {
            $tenant = Tenant::create([
                'name' => $request->name,
                'email' => $request->email,
                'phone' => $request->phone,
                'address' => $request->address,
                'tax_id' => $request->tax_id,
                'currency' => $request->currency ?? 'KES',
                'trial_ends_at' => now()->addDays(7),
            ]);

            User::create([
                'tenant_id' => $tenant->id,
                'name' => $request->admin_name,
                'email' => $request->admin_email,
                'password' => $request->admin_password,
                'role' => 'admin',
            ]);

            $tenant->loadCount('users');

            return response()->json(['data' => $tenant], 201);
        });
    }

    public function show(Tenant $tenant)
    {
        $this->authorize();

        $tenant->loadCount('users');
        $tenant->subscription_status = $tenant->subscriptionStatus();
        $tenant->days_remaining = $tenant->daysRemaining();
        $tenant->expires_at = $this->getExpiresAt($tenant);

        return response()->json(['data' => $tenant]);
    }

    public function update(Request $request, Tenant $tenant)
    {
        $this->authorize();

        $request->validate([
            'name' => 'required|string|max:255',
            'email' => 'required|email|max:255',
            'phone' => 'nullable|string|max:20',
            'address' => 'nullable|string|max:500',
            'tax_id' => 'nullable|string|max:50',
            'currency' => 'nullable|string|max:10',
        ]);

        $tenant->update($request->only(['name', 'email', 'phone', 'address', 'tax_id', 'currency']));
        $tenant->loadCount('users');

        return response()->json(['data' => $tenant]);
    }

    public function impersonate(Tenant $tenant)
    {
        $this->authorize();

        $adminUser = User::where('tenant_id', $tenant->id)
            ->where('role', 'admin')
            ->where('is_active', true)
            ->first();

        if (!$adminUser) {
            return response()->json(['message' => 'No active admin user found for this tenant.'], 422);
        }

        $token = $adminUser->createToken('impersonate')->plainTextToken;
        $adminUser->load('tenant');

        return response()->json([
            'user' => $adminUser,
            'token' => $token,
            'subscription_status' => $tenant->subscriptionStatus(),
            'days_remaining' => $tenant->daysRemaining(),
        ]);
    }

    public function toggleActive(Tenant $tenant)
    {
        $this->authorize();

        $tenant->update(['is_active' => !$tenant->is_active]);
        $tenant->loadCount('users');

        return response()->json(['data' => $tenant]);
    }

    public function confirmSubscriptionPayment(Request $request, TenantSubscription $tenantSubscription)
    {
        $this->authorize();

        $request->validate([
            'payment_reference' => 'nullable|string|max:255',
        ]);

        if ($tenantSubscription->status !== 'pending') {
            return response()->json(['message' => 'This subscription is not pending payment.'], 422);
        }

        $service = new SubscriptionService();
        $service->confirmPayment(
            $tenantSubscription,
            auth()->user(),
            $request->input('payment_reference'),
        );

        $tenantSubscription->refresh()->load('plan');

        return response()->json([
            'message' => 'Payment confirmed and subscription activated.',
            'data' => $tenantSubscription,
        ]);
    }

    private function getExpiresAt(Tenant $tenant): ?string
    {
        if ($tenant->hasActiveSubscription()) {
            $sub = $tenant->activeSubscription;
            return $sub?->ends_at?->toISOString();
        }

        if ($tenant->isOnTrial()) {
            return $tenant->trial_ends_at?->toISOString();
        }

        return null;
    }
}
