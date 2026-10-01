<?php

namespace App\Http\Controllers\Auth;

use App\Helpers\PhoneHelper;
use App\Http\Controllers\Controller;
use App\Models\Client;
use App\Models\ClientUser;
use App\Models\User;
use App\Services\TwoFactorChallengeService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

class LoginController extends Controller
{
    public function login(Request $request)
    {
        $request->validate([
            'identifier' => 'required|string',
            'password' => 'required',
            // Set on the second request, once the caller has picked which
            // of two matching accounts they meant (see the "both match"
            // branch below) — skips straight to that account.
            'account_type' => 'nullable|in:staff,client',
        ]);

        $identifier = $request->identifier;
        $isEmail = filter_var($identifier, FILTER_VALIDATE_EMAIL);

        $user = $isEmail
            ? User::where('email', $identifier)->first()
            : PhoneHelper::wherePhone(User::query(), 'phone', $identifier)->first();
        $userMatches = $user && Hash::check($request->password, $user->password);

        $clientUser = $isEmail
            ? ClientUser::where('email', $identifier)->first()
            : PhoneHelper::wherePhone(ClientUser::query(), 'phone', $identifier)->first();
        $clientUserMatches = $clientUser && Hash::check($request->password, $clientUser->password);

        // The same identifier+password is valid for both a staff account and
        // a client/portal account — two genuinely different people/
        // businesses who happen to share an email or phone (e.g. a reseller
        // who is ALSO a regular client of ours). Previously this silently
        // always picked the staff account and the client account was
        // unreachable through login at all. Let the caller say which one
        // they meant instead.
        if ($userMatches && $clientUserMatches && !$request->account_type) {
            return response()->json([
                'requires_account_choice' => true,
                'message' => 'This email/phone matches two accounts — choose which to sign into.',
                'accounts' => [
                    ['type' => 'staff', 'label' => $user->tenant?->name ? "Staff — {$user->tenant->name}" : 'Staff account'],
                    ['type' => 'client', 'label' => $clientUser->tenant?->name ? "Client — {$clientUser->tenant->name}" : 'Client account'],
                ],
            ], 300);
        }

        if ($request->account_type === 'client' && $clientUserMatches) {
            return $this->loginClientUser($clientUser);
        }
        if ($request->account_type === 'staff' && $userMatches) {
            return $this->loginTenantUser($user);
        }

        if ($userMatches) {
            return $this->loginTenantUser($user);
        }

        if ($clientUserMatches) {
            return $this->loginClientUser($clientUser);
        }

        // Identifier belongs to a known client (e.g. imported from WHMCS) who
        // has no portal login yet — they already have a real account and
        // billing history, they just need to verify and set a password, not
        // "sign up". Just signal it; /portal/forgot-password (email, SMS, AND
        // WhatsApp OTP) owns actually sending the code, so it's sent exactly
        // once by exactly one system.
        $client = $isEmail
            ? Client::where('email', $identifier)->first()
            : PhoneHelper::wherePhone(Client::query(), 'phone', $identifier)->first();
        if ($client && ($client->email || $client->phone)) {
            return response()->json([
                'requires_otp' => true,
                'message'      => 'This account has no portal password set yet — verify to continue.',
                'client_name'  => $client->name,
            ], 449); // Custom status code to signal OTP required
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

        if ($user->hasEnabledTwoFactorAuth()) {
            return $this->twoFactorChallengeResponse('tenant', $user->id);
        }

        return $this->issueTenantToken($user);
    }

    /** Also called by TwoFactorAuthController::verifyLogin() once the second factor checks out. */
    public function issueTenantToken(User $user)
    {
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

        if ($clientUser->hasEnabledTwoFactorAuth()) {
            return $this->twoFactorChallengeResponse('client', $clientUser->id);
        }

        return $this->issueClientToken($clientUser);
    }

    /** Also called by TwoFactorAuthController::verifyLogin() once the second factor checks out. */
    public function issueClientToken(ClientUser $clientUser)
    {
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

    private function twoFactorChallengeResponse(string $type, string $id)
    {
        $challengeId = app(TwoFactorChallengeService::class)->create($type, $id);

        return response()->json([
            'requires_2fa' => true,
            'challenge_id' => $challengeId,
            'message'      => 'Enter the 6-digit code from your authenticator app.',
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
        if ($user->supervisor_id) {
            $user->load('supervisor:id,name,email');
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
