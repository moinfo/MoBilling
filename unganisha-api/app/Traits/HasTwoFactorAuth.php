<?php

namespace App\Traits;

use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use PragmaRX\Google2FA\Google2FA;

/**
 * Shared TOTP (authenticator-app) 2FA behavior for both staff `User` and
 * portal `ClientUser` — both get identical two_factor_secret /
 * two_factor_recovery_codes / two_factor_confirmed_at columns (see
 * 2026_08_10_140000_add_two_factor_auth_columns migration) and identical
 * logic, so it lives here once instead of being duplicated per model.
 */
trait HasTwoFactorAuth
{
    public function hasEnabledTwoFactorAuth(): bool
    {
        return !is_null($this->two_factor_confirmed_at) && !is_null($this->two_factor_secret);
    }

    /**
     * Start (or restart) setup: generate a fresh secret, not yet confirmed.
     * Returns the secret (for manual entry) and the otpauth:// URI the
     * frontend renders as a QR code — no server-side QR image generation.
     */
    public function initializeTwoFactorAuth(string $issuer, string $label): array
    {
        $google2fa = new Google2FA();
        $secret = $google2fa->generateSecretKey();

        $this->forceFill([
            'two_factor_secret'         => $secret,
            'two_factor_confirmed_at'   => null,
            'two_factor_recovery_codes' => null,
        ])->save();

        return [
            'secret'      => $secret,
            'otpauth_url' => $google2fa->getQRCodeUrl($issuer, $label, $secret),
        ];
    }

    /** Verify a 6-digit code against the (pending or confirmed) secret. */
    public function verifyTwoFactorCode(string $code): bool
    {
        if (!$this->two_factor_secret) {
            return false;
        }

        // window=1 tolerates ±30s clock drift between the phone and server.
        return (new Google2FA())->verifyKey($this->two_factor_secret, $code, 1) === true;
    }

    /**
     * Finish setup: verify the code, mark confirmed, generate recovery
     * codes. Returns the plaintext codes (shown to the user exactly once —
     * only their hashes are stored) or null if the code didn't match.
     */
    public function confirmTwoFactorAuth(string $code): ?array
    {
        if (!$this->verifyTwoFactorCode($code)) {
            return null;
        }

        $plainCodes = $this->freshRecoveryCodes();

        $this->forceFill([
            'two_factor_confirmed_at'   => now(),
            'two_factor_recovery_codes' => array_map(fn ($c) => Hash::make($c), $plainCodes),
        ])->save();

        return $plainCodes;
    }

    /** Consume a recovery code (single use, case-insensitive). */
    public function useTwoFactorRecoveryCode(string $code): bool
    {
        $hashes = $this->two_factor_recovery_codes ?? [];
        $code = strtoupper(trim($code));

        foreach ($hashes as $i => $hash) {
            if (Hash::check($code, $hash)) {
                unset($hashes[$i]);
                $this->forceFill(['two_factor_recovery_codes' => array_values($hashes)])->save();
                return true;
            }
        }

        return false;
    }

    public function twoFactorRecoveryCodesRemaining(): int
    {
        return count($this->two_factor_recovery_codes ?? []);
    }

    /** Replace all recovery codes (e.g. running low) — 2FA must already be confirmed. */
    public function regenerateTwoFactorRecoveryCodes(): array
    {
        $plainCodes = $this->freshRecoveryCodes();

        $this->forceFill([
            'two_factor_recovery_codes' => array_map(fn ($c) => Hash::make($c), $plainCodes),
        ])->save();

        return $plainCodes;
    }

    public function disableTwoFactorAuth(): void
    {
        $this->forceFill([
            'two_factor_secret'         => null,
            'two_factor_recovery_codes' => null,
            'two_factor_confirmed_at'   => null,
        ])->save();
    }

    private function freshRecoveryCodes(): array
    {
        return collect(range(1, 8))
            ->map(fn () => Str::upper(Str::random(4) . '-' . Str::random(4)))
            ->all();
    }
}
