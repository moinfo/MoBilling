<?php

namespace App\Http\Controllers\Auth;

use App\Helpers\PhoneHelper;
use App\Http\Controllers\Controller;
use App\Models\Client;
use App\Models\ClientUser;
use App\Models\User;
use App\Notifications\PortalOtpNotification;
use App\Services\SmsService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Notification;
use Illuminate\Validation\ValidationException;

class LoginController extends Controller
{
    public function login(Request $request)
    {
        $request->validate([
            'identifier' => 'required|string',
            'password' => 'required',
        ]);

        $identifier = $request->identifier;
        $isEmail = filter_var($identifier, FILTER_VALIDATE_EMAIL);

        // Try tenant/admin user first
        $user = $isEmail
            ? User::where('email', $identifier)->first()
            : PhoneHelper::wherePhone(User::query(), 'phone', $identifier)->first();

        if ($user && Hash::check($request->password, $user->password)) {
            return $this->loginTenantUser($user);
        }

        // Try client portal user
        $clientUser = $isEmail
            ? ClientUser::where('email', $identifier)->first()
            : PhoneHelper::wherePhone(ClientUser::query(), 'phone', $identifier)->first();

        if ($clientUser && Hash::check($request->password, $clientUser->password)) {
            return $this->loginClientUser($clientUser);
        }

        // Check if identifier belongs to a client without a portal account → send OTP
        $client = $isEmail
            ? Client::where('email', $identifier)->first()
            : PhoneHelper::wherePhone(Client::query(), 'phone', $identifier)->first();
        if ($client && $client->email) {
            return $this->sendPortalOtp($client);
        }

        throw ValidationException::withMessages([
            'identifier' => ['The provided credentials are incorrect.'],
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

    private function sendPortalOtp(Client $client)
    {
        $email = $client->email;

        // Rate limit: max 3 OTPs per email per hour
        $recentCount = DB::table('portal_otps')
            ->where('email', $email)
            ->where('created_at', '>=', now()->subHour())
            ->count();

        if ($recentCount >= 10) {
            throw ValidationException::withMessages([
                'email' => ['Too many verification requests. Please try again later.'],
            ]);
        }

        $otp = str_pad(random_int(0, 999999), 6, '0', STR_PAD_LEFT);

        DB::table('portal_otps')->insert([
            'email' => $email,
            'otp' => $otp,
            'client_id' => $client->id,
            'tenant_id' => $client->tenant_id,
            'expires_at' => now()->addMinutes(10),
            'verified' => false,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $tenant = $client->tenant;
        $tenantName = $tenant?->name ?? 'MoBilling';
        Notification::route('mail', $email)
            ->notify(new PortalOtpNotification($otp, $tenantName));

        // Also send via SMS if phone available and tenant has SMS enabled
        if ($client->phone && $tenant && $tenant->sms_enabled && $tenant->sms_authorization) {
            try {
                app(SmsService::class)->send(
                    $tenant,
                    $client->phone,
                    "Your MoBilling verification code is: {$otp}. It expires in 10 minutes."
                );
            } catch (\Throwable $e) {
                // SMS failed — email was still sent
            }
        }

        return response()->json([
            'requires_otp' => true,
            'message' => 'Verification code sent to your email.',
            'client_name' => $client->name,
        ], 449); // Custom status code to signal OTP required
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
