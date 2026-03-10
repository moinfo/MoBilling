<?php

namespace App\Http\Controllers\Portal;

use App\Http\Controllers\Controller;
use App\Models\Client;
use App\Models\ClientUser;
use App\Notifications\PortalOtpNotification;
use App\Services\SmsService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Notification;
use Illuminate\Validation\ValidationException;

class PortalAuthController extends Controller
{
    /**
     * Step 1: Client enters email → we check if it matches a client, send OTP.
     */
    public function requestOtp(Request $request)
    {
        $request->validate([
            'email' => 'required|email',
        ]);

        $email = $request->email;

        // Check if already has a portal account
        $existingUser = ClientUser::where('email', $email)->first();
        if ($existingUser) {
            return response()->json([
                'has_account' => true,
                'message' => 'You already have a portal account. Please log in.',
            ]);
        }

        // Find client by email
        $client = Client::where('email', $email)->first();

        if (!$client) {
            throw ValidationException::withMessages([
                'email' => ['No client account found with this email. Please contact your service provider.'],
            ]);
        }

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

        // Generate 6-digit OTP
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

        // Send OTP via email
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
            'has_account' => false,
            'message' => 'Verification code sent to your email.',
            'client_name' => $client->name,
        ]);
    }

    /**
     * Step 2: Verify OTP and create portal account with password.
     */
    public function verifyAndRegister(Request $request)
    {
        $request->validate([
            'email' => 'required|email',
            'otp' => 'required|string|size:6',
            'name' => 'required|string|max:255',
            'password' => 'required|min:8|confirmed',
            'phone' => 'nullable|string|max:20',
        ]);

        $record = DB::table('portal_otps')
            ->where('email', $request->email)
            ->where('otp', $request->otp)
            ->where('verified', false)
            ->where('expires_at', '>', now())
            ->orderByDesc('created_at')
            ->first();

        if (!$record) {
            throw ValidationException::withMessages([
                'otp' => ['Invalid or expired verification code.'],
            ]);
        }

        // Check if account was created in the meantime
        $existingUser = ClientUser::where('email', $request->email)
            ->where('tenant_id', $record->tenant_id)
            ->first();

        if ($existingUser) {
            return response()->json([
                'message' => 'Account already exists. Please log in.',
                'has_account' => true,
            ], 409);
        }

        // Mark OTP as verified
        DB::table('portal_otps')
            ->where('id', $record->id)
            ->update(['verified' => true]);

        // Create client user (first user is admin)
        $isFirst = ClientUser::where('client_id', $record->client_id)->count() === 0;

        $clientUser = ClientUser::create([
            'client_id' => $record->client_id,
            'tenant_id' => $record->tenant_id,
            'name' => $request->name,
            'email' => $request->email,
            'password' => $request->password,
            'phone' => $request->phone,
            'role' => $isFirst ? 'admin' : 'viewer',
            'last_login_at' => now(),
        ]);

        // Auto-login
        $token = $clientUser->createToken('client-portal-token')->plainTextToken;
        $clientUser->load('client', 'tenant');

        // Cleanup old OTPs for this email
        DB::table('portal_otps')
            ->where('email', $request->email)
            ->delete();

        return response()->json([
            'user' => $clientUser,
            'token' => $token,
            'user_type' => 'client',
            'permissions' => $clientUser->isPortalAdmin()
                ? ['portal.view', 'portal.profile', 'portal.users']
                : ['portal.view', 'portal.profile'],
            'message' => 'Account created successfully.',
        ]);
    }
}
