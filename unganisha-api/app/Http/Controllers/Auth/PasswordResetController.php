<?php

namespace App\Http\Controllers\Auth;

use App\Helpers\PhoneHelper;
use App\Http\Controllers\Controller;
use App\Models\Client;
use App\Models\ClientUser;
use App\Models\Tenant;
use App\Models\User;
use App\Notifications\PortalOtpNotification;
use App\Services\SmsService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Notification;
use Illuminate\Support\Str;
use Illuminate\Validation\Rules\Password as PasswordRule;
use Illuminate\Validation\ValidationException;

class PasswordResetController extends Controller
{
    /**
     * Resolve the target: User, ClientUser, or Client (unregistered).
     * Returns [target, type] where type is 'user', 'client_user', or 'client'.
     */
    private function resolveTarget(string $identifier): array
    {
        $isEmail = filter_var($identifier, FILTER_VALIDATE_EMAIL);

        // Staff user
        $user = $isEmail
            ? User::where('email', $identifier)->first()
            : PhoneHelper::wherePhone(User::query(), 'phone', $identifier)->first();
        if ($user) return [$user, 'user'];

        // Portal user (already registered)
        $clientUser = $isEmail
            ? ClientUser::where('email', $identifier)->first()
            : PhoneHelper::wherePhone(ClientUser::query(), 'phone', $identifier)->first();
        if ($clientUser) return [$clientUser, 'client_user'];

        // Client record (not yet registered for portal)
        $client = $isEmail
            ? Client::where('email', $identifier)->first()
            : PhoneHelper::wherePhone(Client::query(), 'phone', $identifier)->first();
        if ($client) return [$client, 'client'];

        return [null, null];
    }

    /**
     * Step 1: Send OTP to the user's email for password reset or account setup.
     */
    public function forgotPassword(Request $request)
    {
        $request->validate([
            'identifier' => 'required|string',
        ]);

        [$target, $type] = $this->resolveTarget($request->identifier);

        if (!$target) {
            throw ValidationException::withMessages([
                'identifier' => ['No account found with that email or phone.'],
            ]);
        }

        $email = $target->email;
        if (!$email) {
            throw ValidationException::withMessages([
                'identifier' => ['No email address on this account to send verification code.'],
            ]);
        }

        // Rate limit: max 3 per hour
        $recentCount = DB::table('portal_otps')
            ->where('email', $email)
            ->where('created_at', '>=', now()->subHour())
            ->count();

        if ($recentCount >= 10) {
            throw ValidationException::withMessages([
                'identifier' => ['Too many requests. Please try again later.'],
            ]);
        }

        $otp = str_pad(random_int(0, 999999), 6, '0', STR_PAD_LEFT);

        DB::table('portal_otps')->insert([
            'email' => $email,
            'otp' => $otp,
            'client_id' => $type === 'client' ? $target->id : ($target->client_id ?? null),
            'tenant_id' => $target->tenant_id ?? null,
            'expires_at' => now()->addMinutes(10),
            'verified' => false,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        // Send OTP via email
        Notification::route('mail', $email)
            ->notify(new PortalOtpNotification($otp, 'MoBilling'));

        // Send OTP via SMS if phone available and tenant has SMS enabled
        $smsSent = false;
        $phone = $target->phone;
        $tenant = $target->tenant_id ? Tenant::find($target->tenant_id) : null;

        if ($phone && $tenant && $tenant->sms_enabled && $tenant->sms_authorization) {
            try {
                app(SmsService::class)->send(
                    $tenant,
                    $phone,
                    "Your MoBilling verification code is: {$otp}. It expires in 10 minutes."
                );
                $smsSent = true;
            } catch (\Throwable $e) {
                // SMS failed — email was still sent, so continue
            }
        }

        $sentTo = $smsSent ? 'your email and phone' : 'your email';

        return response()->json([
            'message' => "Verification code sent to {$sentTo}.",
            'email_hint' => Str::mask($email, '*', 3, -strpos(strrev($email), '@') - 1),
            'requires_registration' => $type === 'client',
        ]);
    }

    /**
     * Step 2: Verify OTP only (before showing password/registration form).
     */
    public function verifyOtp(Request $request)
    {
        $request->validate([
            'identifier' => 'required|string',
            'otp' => 'required|string|size:6',
        ]);

        [$target, $type] = $this->resolveTarget($request->identifier);

        if (!$target) {
            throw ValidationException::withMessages([
                'identifier' => ['Account not found.'],
            ]);
        }

        $record = DB::table('portal_otps')
            ->where('email', $target->email)
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

        // Mark OTP as verified
        DB::table('portal_otps')->where('id', $record->id)->update(['verified' => true]);

        return response()->json([
            'message' => 'Code verified successfully.',
            'requires_registration' => $type === 'client',
            'client_name' => $type === 'client' ? $target->name : null,
        ]);
    }

    /**
     * Step 3: Reset password (existing account) or create portal account (new client).
     */
    public function resetPassword(Request $request)
    {
        [$target, $type] = $this->resolveTarget($request->identifier);

        if ($type === 'client') {
            return $this->createPortalAccount($request, $target);
        }

        return $this->doResetPassword($request, $target);
    }

    /**
     * Reset password for an existing User or ClientUser.
     */
    private function doResetPassword(Request $request, $target)
    {
        $request->validate([
            'identifier' => 'required|string',
            'otp' => 'required|string|size:6',
            'password' => ['required', 'confirmed', PasswordRule::min(8)],
        ]);

        if (!$target) {
            throw ValidationException::withMessages([
                'identifier' => ['Account not found.'],
            ]);
        }

        // Check OTP was verified
        $record = DB::table('portal_otps')
            ->where('email', $target->email)
            ->where('otp', $request->otp)
            ->where('verified', true)
            ->where('expires_at', '>', now())
            ->orderByDesc('created_at')
            ->first();

        if (!$record) {
            throw ValidationException::withMessages([
                'otp' => ['Invalid or expired verification code. Please start over.'],
            ]);
        }

        $target->forceFill(['password' => Hash::make($request->password)])->save();

        DB::table('portal_otps')->where('email', $target->email)->delete();

        return response()->json(['message' => 'Password has been reset successfully.']);
    }

    /**
     * Create a new portal account for a Client who doesn't have one yet.
     */
    private function createPortalAccount(Request $request, Client $client)
    {
        $request->validate([
            'identifier' => 'required|string',
            'otp' => 'required|string|size:6',
            'password' => ['required', 'confirmed', PasswordRule::min(8)],
        ]);

        // Check OTP was verified
        $record = DB::table('portal_otps')
            ->where('email', $client->email)
            ->where('otp', $request->otp)
            ->where('verified', true)
            ->where('expires_at', '>', now())
            ->orderByDesc('created_at')
            ->first();

        if (!$record) {
            throw ValidationException::withMessages([
                'otp' => ['Invalid or expired verification code. Please start over.'],
            ]);
        }

        // First portal user for this client gets admin role
        $isFirst = ClientUser::where('client_id', $client->id)->count() === 0;

        $clientUser = ClientUser::create([
            'client_id' => $client->id,
            'tenant_id' => $client->tenant_id,
            'name' => $client->name,
            'email' => $client->email,
            'password' => $request->password,
            'phone' => $client->phone,
            'role' => $isFirst ? 'admin' : 'viewer',
            'last_login_at' => now(),
        ]);

        DB::table('portal_otps')->where('email', $client->email)->delete();

        // Auto-login
        $token = $clientUser->createToken('client-portal-token')->plainTextToken;
        $clientUser->load('client', 'tenant');

        return response()->json([
            'message' => 'Account created successfully.',
            'user' => $clientUser,
            'token' => $token,
            'user_type' => 'client',
            'permissions' => $clientUser->isPortalAdmin()
                ? ['portal.view', 'portal.profile', 'portal.users']
                : ['portal.view', 'portal.profile'],
        ]);
    }
}
