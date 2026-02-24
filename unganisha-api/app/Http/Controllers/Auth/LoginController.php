<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
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

        $user = User::where('email', $request->email)->first();

        if (!$user || !Hash::check($request->password, $user->password)) {
            throw ValidationException::withMessages([
                'email' => ['The provided credentials are incorrect.'],
            ]);
        }

        if (!$user->is_active) {
            throw ValidationException::withMessages([
                'email' => ['Your account has been deactivated.'],
            ]);
        }

        // Check tenant is admin-deactivated (skip for super_admin who has no tenant)
        if (!$user->isSuperAdmin() && $user->tenant && !$user->tenant->is_active) {
            throw ValidationException::withMessages([
                'email' => ['Your organization has been deactivated.'],
            ]);
        }

        $token = $user->createToken('auth-token')->plainTextToken;

        // Only load tenant if user has one
        if ($user->tenant_id) {
            $user->load('tenant');
        }

        $response = [
            'user' => $user,
            'token' => $token,
        ];

        // Append subscription info for tenant users
        if ($user->tenant_id && $user->tenant) {
            $response['subscription_status'] = $user->tenant->subscriptionStatus();
            $response['days_remaining'] = $user->tenant->daysRemaining();
        }

        return response()->json($response);
    }

    public function logout(Request $request)
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json(['message' => 'Logged out successfully']);
    }

    public function me(Request $request)
    {
        $user = $request->user();

        if ($user->tenant_id) {
            $user->load('tenant');
        }

        $response = [
            'user' => $user,
        ];

        // Append subscription info for tenant users
        if ($user->tenant_id && $user->tenant) {
            $response['subscription_status'] = $user->tenant->subscriptionStatus();
            $response['days_remaining'] = $user->tenant->daysRemaining();
        }

        return response()->json($response);
    }
}
