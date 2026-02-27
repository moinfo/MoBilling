<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use App\Models\Permission;
use App\Models\Role;
use App\Models\Tenant;
use App\Models\User;
use App\Notifications\NewTenantNotification;
use App\Notifications\WelcomeNotification;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Notification;
use Illuminate\Validation\Rules\Password;

class RegisterController extends Controller
{
    public function register(Request $request)
    {
        $request->validate([
            'company_name' => 'required|string|max:255',
            'name' => 'required|string|max:255',
            'email' => 'required|email|unique:users,email',
            'password' => ['required', 'confirmed', Password::min(8)],
            'phone' => 'nullable|string|max:20',
        ]);

        return DB::transaction(function () use ($request) {
            $tenant = Tenant::create([
                'name' => $request->company_name,
                'email' => $request->email,
                'phone' => $request->phone,
                'trial_ends_at' => now()->addDays(7),
            ]);

            // Grant all permissions to new tenant
            $allPermissionIds = Permission::pluck('id');
            $tenant->allowedPermissions()->sync($allPermissionIds);

            // Create default admin role with all permissions
            $adminRole = Role::create([
                'tenant_id' => $tenant->id,
                'name' => 'admin',
                'label' => 'Administrator',
                'is_system' => true,
            ]);
            $adminRole->permissions()->sync($allPermissionIds);

            // Create default user role with limited permissions
            $userRole = Role::create([
                'tenant_id' => $tenant->id,
                'name' => 'user',
                'label' => 'User',
                'is_system' => true,
            ]);
            $userPermNames = [
                'menu.dashboard', 'menu.clients', 'menu.products',
                'menu.quotations', 'menu.proformas', 'menu.invoices',
                'menu.payments_in', 'menu.client_subscriptions', 'menu.next_bills',
                'menu.collection', 'menu.followups',
                'menu.statutories', 'menu.statutory_bills', 'menu.bill_categories', 'menu.payments_out',
                'menu.expense_categories', 'menu.expenses',
                'menu.automation', 'menu.reports', 'menu.sms',
                'clients.read', 'products.read', 'documents.read',
                'payments_in.read', 'client_subscriptions.read',
                'statutories.read', 'bills.read', 'payments_out.read',
                'expense_categories.read', 'expenses.read',
                'documents.create', 'documents.update', 'documents.send', 'documents.download',
                'payments_in.create', 'payments_in.update',
                'expenses.create', 'expenses.update',
                'settings.profile',
                'reports.revenue', 'reports.aging', 'reports.client_statement',
                'reports.payment_collection', 'reports.expense', 'reports.profit_loss',
                'reports.statutory', 'reports.subscription', 'reports.collection',
                'reports.communication',
            ];
            $userPermIds = Permission::whereIn('name', $userPermNames)->pluck('id');
            $userRole->permissions()->sync($userPermIds);

            $user = User::create([
                'tenant_id' => $tenant->id,
                'name' => $request->name,
                'email' => $request->email,
                'password' => $request->password,
                'phone' => $request->phone,
                'role' => 'admin',
                'role_id' => $adminRole->id,
            ]);

            $user->notify(new WelcomeNotification($tenant));

            // Notify all super admins about the new tenant
            $superAdmins = User::where('role', 'super_admin')->get();
            Notification::send($superAdmins, new NewTenantNotification($tenant));

            $token = $user->createToken('auth-token')->plainTextToken;

            $user->load('role.permissions');

            return response()->json([
                'user' => $user->load('tenant'),
                'token' => $token,
                'permissions' => $user->getPermissionNames(),
                'subscription_status' => 'trial',
                'days_remaining' => 7,
            ], 201);
        });
    }
}
