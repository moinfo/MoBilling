<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use App\Models\ClientUser;
use App\Models\User;
use App\Services\TwoFactorChallengeService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

class TwoFactorAuthController extends Controller
{
    public function __construct(private TwoFactorChallengeService $challenges)
    {
    }

    /** Self-service: current status for the authenticated user (staff or portal client). */
    public function status(Request $request)
    {
        $user = $request->user();

        return response()->json([
            'enabled'                  => $user->hasEnabledTwoFactorAuth(),
            'recovery_codes_remaining' => $user->hasEnabledTwoFactorAuth() ? $user->twoFactorRecoveryCodesRemaining() : null,
        ]);
    }

    /** Start setup: generates a new (unconfirmed) secret + QR payload. */
    public function enable(Request $request)
    {
        $user = $request->user();
        abort_if($user->hasEnabledTwoFactorAuth(), 422, 'Two-factor authentication is already enabled.');

        $tenant = $user->tenant;
        $issuer = $tenant?->name ?: 'MoBilling';
        $label = $user->email ?: $user->phone ?: $user->name;

        $init = $user->initializeTwoFactorAuth($issuer, $label);

        return response()->json(['data' => $init]);
    }

    /** Finish setup: verify the first code, activate, and hand back one-time-viewable recovery codes. */
    public function confirm(Request $request)
    {
        $data = $request->validate(['code' => 'required|string']);
        $user = $request->user();

        $codes = $user->confirmTwoFactorAuth(trim($data['code']));
        if (!$codes) {
            return response()->json(['message' => 'That code was not correct — please try again.'], 422);
        }

        return response()->json([
            'message'        => 'Two-factor authentication is now enabled.',
            'recovery_codes' => $codes,
        ]);
    }

    /** Turn it off — requires the current password as confirmation. */
    public function disable(Request $request)
    {
        $data = $request->validate(['password' => 'required|string']);
        $user = $request->user();

        abort_unless(Hash::check($data['password'], $user->password), 422, 'Incorrect password.');

        $user->disableTwoFactorAuth();

        return response()->json(['message' => 'Two-factor authentication has been disabled.']);
    }

    /** Replace recovery codes (e.g. running low) — requires password confirmation. */
    public function regenerateRecoveryCodes(Request $request)
    {
        $data = $request->validate(['password' => 'required|string']);
        $user = $request->user();

        abort_unless(Hash::check($data['password'], $user->password), 422, 'Incorrect password.');
        abort_unless($user->hasEnabledTwoFactorAuth(), 422, 'Two-factor authentication is not enabled.');

        return response()->json(['recovery_codes' => $user->regenerateTwoFactorRecoveryCodes()]);
    }

    /**
     * Login-time second factor. Public (no auth yet) — the short-lived,
     * high-entropy challenge_id from LoginController is the credential that
     * proves the password step already passed.
     */
    public function verifyLogin(Request $request)
    {
        $data = $request->validate([
            'challenge_id'  => 'required|string',
            'code'          => 'nullable|string',
            'recovery_code' => 'nullable|string',
        ]);

        if (empty($data['code']) && empty($data['recovery_code'])) {
            throw ValidationException::withMessages(['code' => ['Enter your 6-digit code or a recovery code.']]);
        }

        $challenge = $this->challenges->resolve($data['challenge_id']);
        if (!$challenge) {
            throw ValidationException::withMessages(['challenge_id' => ['This login attempt has expired — please sign in again.']]);
        }

        $user = $challenge['type'] === 'tenant'
            ? User::find($challenge['id'])
            : ClientUser::find($challenge['id']);

        if (!$user || !$user->hasEnabledTwoFactorAuth()) {
            $this->challenges->forget($data['challenge_id']);
            throw ValidationException::withMessages(['challenge_id' => ['This login attempt is no longer valid — please sign in again.']]);
        }

        $ok = !empty($data['recovery_code'])
            ? $user->useTwoFactorRecoveryCode($data['recovery_code'])
            : $user->verifyTwoFactorCode($data['code']);

        if (!$ok) {
            $this->challenges->registerFailedAttempt($data['challenge_id']);
            throw ValidationException::withMessages(['code' => ['That code was not correct.']]);
        }

        $this->challenges->forget($data['challenge_id']);

        $login = app(LoginController::class);

        return $challenge['type'] === 'tenant'
            ? $login->issueTenantToken($user)
            : $login->issueClientToken($user);
    }
}
