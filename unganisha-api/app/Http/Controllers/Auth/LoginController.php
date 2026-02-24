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

        // Check tenant is active (skip for super_admin who has no tenant)
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

        return response()->json([
            'user' => $user,
            'token' => $token,
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

        if ($user->tenant_id) {
            $user->load('tenant');
        }

        return response()->json([
            'user' => $user,
        ]);
    }
}
