<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
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

            $user = User::create([
                'tenant_id' => $tenant->id,
                'name' => $request->name,
                'email' => $request->email,
                'password' => $request->password,
                'phone' => $request->phone,
                'role' => 'admin',
            ]);

            $user->notify(new WelcomeNotification($tenant));

            // Notify all super admins about the new tenant
            $superAdmins = User::where('role', 'super_admin')->get();
            Notification::send($superAdmins, new NewTenantNotification($tenant));

            $token = $user->createToken('auth-token')->plainTextToken;

            return response()->json([
                'user' => $user->load('tenant'),
                'token' => $token,
                'subscription_status' => 'trial',
                'days_remaining' => 7,
            ], 201);
        });
    }
}
