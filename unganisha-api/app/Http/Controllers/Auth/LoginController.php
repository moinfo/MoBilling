<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use App\Models\ClientUser;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

class LoginController extends Controller
{
    public function login(Request $request)
    {
        $request->validate([
            'email' => 'required|email',
            'password' => 'required',
        ]);

        // Try tenant/admin user first
        $user = User::where('email', $request->email)->first();

        if ($user && Hash::check($request->password, $user->password)) {
            return $this->loginTenantUser($user);
        }

        // Try client portal user
        $clientUser = ClientUser::where('email', $request->email)->first();

        if ($clientUser && Hash::check($request->password, $clientUser->password)) {
            return $this->loginClientUser($clientUser);
        }

        throw ValidationException::withMessages([
            'email' => ['The provided credentials are incorrect.'],
        ]);
    }

    private function loginTenantUser(User $user)
    {
        if (!$user->is_active) {
            throw ValidationException::withMessages([
                'email' => ['Your account has been deactivated.'],
            ]);
        }

        if (!$user->isSuperAdmin() && $user->tenant && !$user->tenant->is_active) {
            throw ValidationException::withMessages([
                'email' => ['Your organization has been deactivated.'],
            ]);
        }

        $token = $user->createToken('auth-token')->plainTextToken;

        if ($user->tenant_id) {
            $user->load('tenant');
        }
        if ($user->role_id) {
            $user->load('role.permissions');
        }

        $response = [
            'user' => $user,
            'token' => $token,
            'user_type' => 'tenant',
            'permissions' => $user->isSuperAdmin() ? ['*'] : $user->getPermissionNames(),
        ];

        if ($user->tenant_id && $user->tenant) {
            $response['subscription_status'] = $user->tenant->subscriptionStatus();
            $response['days_remaining'] = $user->tenant->daysRemaining();
        }

        return response()->json($response);
    }

    private function loginClientUser(ClientUser $clientUser)
    {
        if (!$clientUser->is_active) {
            throw ValidationException::withMessages([
                'email' => ['Your account has been deactivated.'],
            ]);
        }

        $tenant = $clientUser->tenant;
        if (!$tenant || !$tenant->is_active) {
            throw ValidationException::withMessages([
                'email' => ['This organization has been deactivated.'],
            ]);
        }

        $clientUser->update(['last_login_at' => now()]);

        $token = $clientUser->createToken('client-portal-token')->plainTextToken;
        $clientUser->load('client', 'tenant');

        return response()->json([
            'user' => $clientUser,
            'token' => $token,
            'user_type' => 'client',
            'permissions' => $clientUser->isPortalAdmin()
                ? ['portal.view', 'portal.profile', 'portal.users']
                : ['portal.view', 'portal.profile'],
        ]);
    }

    public function logout(Request $request)
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json(['message' => 'Logged out successfully']);
    }

    public function me(Request $request)
    {
        $user = $request->user();

        // Client portal user
        if ($user instanceof ClientUser) {
            $user->load('client', 'tenant');

            return response()->json([
                'user' => $user,
                'user_type' => 'client',
                'permissions' => $user->isPortalAdmin()
                    ? ['portal.view', 'portal.profile', 'portal.users']
                    : ['portal.view', 'portal.profile'],
            ]);
        }

        // Tenant/admin user
        if ($user->tenant_id) {
            $user->load('tenant');
        }
        if ($user->role_id) {
            $user->load('role.permissions');
        }

        $response = [
            'user' => $user,
            'user_type' => 'tenant',
            'permissions' => $user->isSuperAdmin() ? ['*'] : $user->getPermissionNames(),
        ];

        if ($user->tenant_id && $user->tenant) {
            $response['subscription_status'] = $user->tenant->subscriptionStatus();
            $response['days_remaining'] = $user->tenant->daysRemaining();
        }

        return response()->json($response);
    }
}
