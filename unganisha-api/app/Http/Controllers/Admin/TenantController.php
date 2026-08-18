<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Client;
use App\Models\Tenant;
use App\Models\TenantSubscription;
use App\Models\User;
use App\Notifications\NewTenantNotification;
use App\Notifications\WelcomeNotification;
use App\Services\SubscriptionService;
use App\Services\TenantProvisioningService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Notification;
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

    /**
     * Turn an existing client into a brand-new, fully independent tenant —
     * their own staff, product catalog, branding, and billing lifecycle. Used
     * when a domain-reseller client wants a real white-label business rather
     * than just wholesale pricing under the current tenant (see
     * ClientController::makeReseller for that unrelated, same-tenant flow).
     *
     * Provisioning mirrors Auth\RegisterController::register() (roles +
     * permissions + notifications) rather than store() above, which never
     * assigns role_id/permissions to its admin user. Nothing about the
     * originating client — invoices, subscriptions, domains, wallet — moves;
     * this only reads its identity fields and leaves an audit note behind.
     */
    public function promoteFromClient(Request $request, TenantProvisioningService $provisioning)
    {
        $this->authorize();

        $request->validate([
            'client_id' => 'required|uuid|exists:clients,id',
            'name' => 'required|string|max:255',
            'email' => 'required|email|max:255',
            'phone' => 'nullable|string|max:20',
            'address' => 'nullable|string|max:500',
            'tax_id' => 'nullable|string|max:50',
            'currency' => 'nullable|string|max:10',
            'admin_name' => 'required|string|max:255',
            'admin_email' => 'required|email|unique:users,email',
            'admin_password' => ['required', Password::min(8)],
            'tier' => 'nullable|in:general,reseller,lite',
        ]);

        $client = Client::withoutGlobalScopes()->with('tenant')->findOrFail($request->client_id);

        return DB::transaction(function () use ($request, $client, $provisioning) {
            // BelongsToTenant::creating() force-sets tenant_id from the
            // *authenticated* caller's own tenant_id on every tenant-scoped
            // model TenantProvisioningService::provision() touches (Role,
            // CommunicationLog via the notification log listeners below,
            // etc). That's a no-op for the public, unauthenticated
            // RegisterController::register(), but here the caller is a
            // logged-in super admin whose own tenant_id is null — which
            // would silently null out (and constraint-violate) every one of
            // those writes. Temporarily pointing the acting user's in-memory
            // tenant_id at a placeholder isn't possible before the tenant
            // exists, so provision() is called first with the acting user's
            // tenant_id patched in immediately after Tenant::create() — see
            // the callback passed below.
            $actingUser = auth()->user();
            $originalTenantId = $actingUser->tenant_id;

            try {
                [$tenant, $adminUser] = $provisioning->provision(
                    [
                        'name' => $request->name,
                        'email' => $request->email,
                        'phone' => $request->phone,
                        'address' => $request->address,
                        'tax_id' => $request->tax_id,
                        'currency' => $request->currency ?? $client->tenant?->currency ?? 'KES',
                        'trial_ends_at' => now()->addDays(7),
                    ],
                    [
                        'name' => $request->admin_name,
                        'email' => $request->admin_email,
                        'password' => $request->admin_password,
                    ],
                    $request->tier ?? 'general',
                    function ($tenant) use ($actingUser) {
                        $actingUser->tenant_id = $tenant->id;
                    },
                );

                $adminUser->notify(new WelcomeNotification($tenant));

                $superAdmins = User::where('role', 'super_admin')->get();
                Notification::send($superAdmins, new NewTenantNotification($tenant));
            } finally {
                $actingUser->tenant_id = $originalTenantId;
            }

            $client->update([
                'notes' => trim(($client->notes ? $client->notes . "\n\n" : '')
                    . "Promoted to independent tenant \"{$tenant->name}\" ({$tenant->id}) on "
                    . now()->toDateString() . ' by ' . auth()->user()->name . '.'),
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

    public function impersonateUser(Tenant $tenant, User $user)
    {
        $this->authorize();

        if ($user->tenant_id !== $tenant->id) {
            return response()->json(['message' => 'User does not belong to this tenant.'], 422);
        }

        if (!$user->is_active) {
            return response()->json(['message' => 'Cannot impersonate an inactive user.'], 422);
        }

        $token = $user->createToken('impersonate')->plainTextToken;
        $user->load('tenant');

        return response()->json([
            'user' => $user,
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
