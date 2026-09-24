<?php

namespace App\Services;

use App\Models\WhatsappVerifyAttempt;

/**
 * Persistent failed-verification counter for the WhatsApp bot. Survives
 * session deletion (unlike the per-session attempts counter), so an attacker
 * cannot reset it by restarting the chat.
 *
 * Customers (surname/email checks): 5 failures inside 24h lock the phone for
 * 1 hour, 10 lock it for 24 hours. Staff PINs (key "staff:<user id>"): 5
 * failures lock for 30 minutes. A success resets the counter.
 */
class WhatsappVerifyGuard
{
    /** failures threshold => lock minutes (highest matching threshold wins) */
    public const CUSTOMER = [5 => 60, 10 => 1440];
    public const STAFF = [5 => 30];
    private const WINDOW_HOURS = 24;

    public static function staffKey(string $userId): string
    {
        return 'staff:' . $userId;
    }

    private function row(string $tenantId, string $key): ?WhatsappVerifyAttempt
    {
        return WhatsappVerifyAttempt::where('tenant_id', $tenantId)->where('phone', $key)->first();
    }

    /** Lock expiry when currently locked, else null. */
    public function isLocked(string $tenantId, string $key): ?\Illuminate\Support\Carbon
    {
        $r = $this->row($tenantId, $key);
        return ($r && $r->locked_until && $r->locked_until->isFuture()) ? $r->locked_until : null;
    }

    /**
     * @return array{failures:int, locked_until:?\Illuminate\Support\Carbon, newly_locked:bool}
     */
    public function recordFailure(string $tenantId, string $key, array $policy = self::CUSTOMER): array
    {
        $r = $this->row($tenantId, $key) ?? new WhatsappVerifyAttempt(['tenant_id' => $tenantId, 'phone' => $key, 'failures' => 0]);

        // Failures older than the window no longer count.
        if ($r->last_failed_at && $r->last_failed_at->lt(now()->subHours(self::WINDOW_HOURS))) {
            $r->failures = 0;
            $r->first_failed_at = now();
        }
        $r->first_failed_at ??= now();
        $r->failures = (int) $r->failures + 1;
        $r->last_failed_at = now();

        $minutes = 0;
        foreach ($policy as $threshold => $mins) {
            if ($r->failures >= $threshold) {
                $minutes = max($minutes, $mins);
            }
        }
        $newlyLocked = false;
        if ($minutes > 0) {
            $until = now()->addMinutes($minutes);
            if (!$r->locked_until || $r->locked_until->lt($until)) {
                $newlyLocked = true;
            }
            $r->locked_until = $until;
        }
        $r->save();

        return ['failures' => $r->failures, 'locked_until' => $minutes > 0 ? $r->locked_until : null, 'newly_locked' => $newlyLocked];
    }

    public function reset(string $tenantId, string $key): void
    {
        WhatsappVerifyAttempt::where('tenant_id', $tenantId)->where('phone', $key)->delete();
    }

    /** True exactly once per lock: the caller should notify staff now. */
    public function claimStaffAlert(string $tenantId, string $key): bool
    {
        $until = $this->isLocked($tenantId, $key);
        if (!$until) {
            return false;
        }
        return \Illuminate\Support\Facades\Cache::add(
            "wa_verify_alert:{$tenantId}:{$key}:" . $until->timestamp, 1, $until->copy()->addMinutes(5)
        );
    }

    public const STOP_WORDS = ['ltd', 'limited', 'co', 'company', 'enterprises', 'enterprise', 'trading', 'group',
        'investment', 'investments', 'services', 'tz', 'inc', 'plc'];

    /**
     * Loose surname check. A company-suffix word ("ltd", "services", ...) or a
     * token shorter than 3 characters never verifies anyone on its own; the
     * client's exact registered last name (people) still matches as before,
     * unless it is itself a stop-word.
     */
    public static function surnameMatches(?string $lastName, ?string $fullName, string $text): bool
    {
        $typed = mb_strtolower(trim($text));
        if ($typed === '' || in_array($typed, self::STOP_WORDS, true)) {
            return false;
        }

        if ($lastName && mb_strtolower(trim($lastName)) === $typed) {
            return true;
        }

        if (mb_strlen($typed) < 3) {
            return false;
        }

        $words = array_filter(
            preg_split('/\s+/', mb_strtolower(trim((string) $fullName))) ?: [],
            fn ($w) => mb_strlen($w) >= 3 && !in_array($w, self::STOP_WORDS, true),
        );

        return in_array($typed, $words, true);
    }
}
