<?php

namespace App\Services;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Str;

/**
 * Short-lived server-side state for the gap between "password verified" and
 * "TOTP code verified" during login — mirrors the Cache-based pattern
 * IdleTimeout already uses for session state, rather than minting a real
 * Sanctum token before the second factor is confirmed.
 */
class TwoFactorChallengeService
{
    private const TTL_MINUTES = 5;
    private const MAX_ATTEMPTS = 5;

    public function create(string $type, string $id): string
    {
        $challengeId = Str::random(40);
        Cache::put($this->key($challengeId), ['type' => $type, 'id' => $id, 'attempts' => 0], now()->addMinutes(self::TTL_MINUTES));

        return $challengeId;
    }

    public function resolve(string $challengeId): ?array
    {
        return Cache::get($this->key($challengeId));
    }

    /** Record a failed attempt; auto-invalidates the challenge after too many. Returns false once locked out. */
    public function registerFailedAttempt(string $challengeId): bool
    {
        $challenge = $this->resolve($challengeId);
        if (!$challenge) {
            return false;
        }

        $challenge['attempts']++;
        if ($challenge['attempts'] >= self::MAX_ATTEMPTS) {
            $this->forget($challengeId);
            return false;
        }

        Cache::put($this->key($challengeId), $challenge, now()->addMinutes(self::TTL_MINUTES));

        return true;
    }

    public function forget(string $challengeId): void
    {
        Cache::forget($this->key($challengeId));
    }

    private function key(string $challengeId): string
    {
        return "2fa_challenge:{$challengeId}";
    }
}
