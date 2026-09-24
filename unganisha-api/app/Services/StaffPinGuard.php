<?php

namespace App\Services;

use App\Models\User;

/**
 * Persistent WhatsApp staff-PIN lockout, stored on the user row so it survives
 * session deletion: 5 wrong PINs inside 24h lock staff-assist for 30 minutes.
 */
class StaffPinGuard
{
    public const MAX_FAILURES = 5;
    public const LOCK_MINUTES = 30;
    private const WINDOW_HOURS = 24;

    public function lockedUntil(User $u): ?\Illuminate\Support\Carbon
    {
        $until = $u->whatsapp_pin_locked_until ? \Illuminate\Support\Carbon::parse($u->whatsapp_pin_locked_until) : null;

        return ($until && $until->isFuture()) ? $until : null;
    }

    /** @return ?\Illuminate\Support\Carbon lock expiry when this failure locked the account */
    public function recordFailure(User $u): ?\Illuminate\Support\Carbon
    {
        $u = User::withoutGlobalScopes()->whereKey($u->id)->first() ?? $u;
        $count = (int) $u->whatsapp_pin_failed_count;
        $last = $u->whatsapp_pin_failed_at ? \Illuminate\Support\Carbon::parse($u->whatsapp_pin_failed_at) : null;
        if ($last && $last->lt(now()->subHours(self::WINDOW_HOURS))) {
            $count = 0;
        }
        $count++;

        $update = ['whatsapp_pin_failed_count' => min($count, 255), 'whatsapp_pin_failed_at' => now()];
        $until = null;
        if ($count >= self::MAX_FAILURES) {
            $until = now()->addMinutes(self::LOCK_MINUTES);
            $update['whatsapp_pin_locked_until'] = $until;
        }
        User::withoutGlobalScopes()->whereKey($u->id)->update($update);

        return $until;
    }

    public function reset(User $u): void
    {
        User::withoutGlobalScopes()->whereKey($u->id)->update([
            'whatsapp_pin_failed_count' => 0, 'whatsapp_pin_failed_at' => null, 'whatsapp_pin_locked_until' => null,
        ]);
    }
}
