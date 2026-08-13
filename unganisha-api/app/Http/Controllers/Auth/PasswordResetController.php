<?php

namespace App\Http\Controllers\Auth;

use App\Helpers\PhoneHelper;
use App\Http\Controllers\Controller;
use App\Models\Client;
use App\Models\ClientUser;
use App\Models\CommunicationLog;
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
     * A stable per-target key for the OTP record — email when the account has
     * one, otherwise the normalized phone. Lets phone-only accounts (common
     * for portal clients) go through forgot-password via SMS/WhatsApp alone.
     */
    private function otpIdentifierFor($target): ?string
    {
        if ($target->email) {
            return $target->email;
        }
        if ($target->phone) {
            return 'phone:' . PhoneHelper::normalize($target->phone);
        }
        return null;
    }

    /**
     * Step 1: Send OTP for password reset or account setup — via email, SMS,
     * and/or WhatsApp, whichever contact details the account has.
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
        $phone = $target->phone;
        $otpKey = $this->otpIdentifierFor($target);

        if (!$otpKey) {
            throw ValidationException::withMessages([
                'identifier' => ['This account has no email or phone number on file to send a verification code to.'],
            ]);
        }

        // Rate limit: max 10 per hour per identifier
        $recentCount = DB::table('portal_otps')
            ->where('identifier', $otpKey)
            ->where('created_at', '>=', now()->subHour())
            ->count();

        if ($recentCount >= 10) {
            throw ValidationException::withMessages([
                'identifier' => ['Too many requests. Please try again later.'],
            ]);
        }

        $otp = str_pad(random_int(0, 999999), 6, '0', STR_PAD_LEFT);
        $clientId = $type === 'client' ? $target->id : ($target->client_id ?? null);

        DB::table('portal_otps')->insert([
            'identifier' => $otpKey,
            'email' => $email,
            'otp' => $otp,
            'client_id' => $clientId,
            'tenant_id' => $target->tenant_id ?? null,
            'expires_at' => now()->addMinutes(10),
            'verified' => false,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $tenant = $target->tenant_id ? Tenant::find($target->tenant_id) : null;

        // Send OTP via email, when the account has one.
        if ($email) {
            Notification::route('mail', $email)
                ->notify(new PortalOtpNotification($otp, 'MoBilling'));
        }

        // Send OTP via SMS if phone available and tenant has SMS enabled
        $smsSent = false;
        $waSent = false;

        if ($phone && app(SmsService::class)->canSend($tenant)) {
            $smsMessage = "Your MoBilling verification code is: {$otp}. It expires in 10 minutes.";
            try {
                app(SmsService::class)->send($tenant, $phone, $smsMessage);
                $smsSent = true;
                CommunicationLog::withoutGlobalScopes()->create([
                    'tenant_id' => $target->tenant_id, 'client_id' => $clientId, 'channel' => 'sms',
                    'type' => 'portal_otp', 'recipient' => $phone, 'message' => $smsMessage, 'status' => 'sent',
                ]);
            } catch (\Throwable $e) {
                // SMS failed — other channels still tried, so continue
                CommunicationLog::withoutGlobalScopes()->create([
                    'tenant_id' => $target->tenant_id, 'client_id' => $clientId, 'channel' => 'sms',
                    'type' => 'portal_otp', 'recipient' => $phone, 'message' => $smsMessage,
                    'status' => 'failed', 'error' => $e->getMessage(),
                ]);
            }
        }

        // Send OTP via WhatsApp too — routes through the tenant's own Meta
        // number or their linked MoSMS account (WhatsAppService dual-mode).
        if ($phone && $tenant && $tenant->whatsapp_enabled && $this->canSendWhatsApp($tenant)) {
            $wa = app(\App\Services\WhatsAppService::class);
            $waMessage = "Your MoBilling verification code is: {$otp}. It expires in 10 minutes.";
            try {
                // Official Meta AUTHENTICATION template (copy-code button).
                $wa->sendTemplate($tenant, $phone, config('whatsapp.otp_template', 'otp_code'), [$otp], config('whatsapp.otp_language', 'en'));
                $waSent = true;
                CommunicationLog::withoutGlobalScopes()->create([
                    'tenant_id' => $target->tenant_id, 'client_id' => $clientId, 'channel' => 'whatsapp',
                    'type' => 'portal_otp', 'recipient' => $phone, 'message' => $waMessage, 'status' => 'sent',
                ]);
            } catch (\Throwable $e) {
                try {
                    // Template unavailable — plain text fallback.
                    $wa->sendText($tenant, $phone, $waMessage);
                    $waSent = true;
                    CommunicationLog::withoutGlobalScopes()->create([
                        'tenant_id' => $target->tenant_id, 'client_id' => $clientId, 'channel' => 'whatsapp',
                        'type' => 'portal_otp', 'recipient' => $phone, 'message' => $waMessage, 'status' => 'sent',
                    ]);
                } catch (\Throwable $e2) {
                    // WhatsApp failed — other channels still tried
                    CommunicationLog::withoutGlobalScopes()->create([
                        'tenant_id' => $target->tenant_id, 'client_id' => $clientId, 'channel' => 'whatsapp',
                        'type' => 'portal_otp', 'recipient' => $phone, 'message' => $waMessage,
                        'status' => 'failed', 'error' => $e2->getMessage(),
                    ]);
                }
            }
        }

        if (!$email && !$smsSent && !$waSent) {
            throw ValidationException::withMessages([
                'identifier' => ['Could not deliver a verification code to this account — please contact support.'],
            ]);
        }

        $channels = array_filter([
            $email ? 'email' : null,
            $smsSent ? 'SMS' : null,
            $waSent ? 'WhatsApp' : null,
        ]);
        $sentTo = match (count($channels)) {
            1 => $channels[array_key_first($channels)],
            2 => implode(' and ', $channels),
            default => implode(', ', array_slice($channels, 0, -1)) . ' and ' . end($channels),
        };

        $hint = $email
            ? Str::mask($email, '*', 3, -strpos(strrev($email), '@') - 1)
            : ($phone ? Str::mask($phone, '*', 2, -2) : null);

        return response()->json([
            'message' => "Verification code sent to your {$sentTo}.",
            'email_hint' => $hint,
            'requires_registration' => $type === 'client',
        ]);
    }

    /** Tenant can deliver WhatsApp: own Meta number, or a linked MoSMS account. */
    private function canSendWhatsApp(Tenant $tenant): bool
    {
        if ($tenant->whatsapp_phone_number_id && $tenant->whatsapp_access_token) {
            return true;
        }
        return app(\App\Services\MosmsService::class)->isLinked($tenant);
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
            ->where('identifier', $this->otpIdentifierFor($target))
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
            ->where('identifier', $this->otpIdentifierFor($target))
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

        DB::table('portal_otps')->where('identifier', $this->otpIdentifierFor($target))->delete();

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

        $otpKey = $this->otpIdentifierFor($client);

        // Check OTP was verified
        $record = DB::table('portal_otps')
            ->where('identifier', $otpKey)
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

        DB::table('portal_otps')->where('identifier', $otpKey)->delete();

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
