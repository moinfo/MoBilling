<?php

namespace App\Console\Commands;

use App\Models\WhatsappReminderTarget;
use App\Models\WhatsappRenewalSession;
use App\Models\WhatsappVerifyAttempt;
use Illuminate\Console\Command;

/**
 * Daily housekeeping for the WhatsApp bot's own tables:
 *  - purge sessions that expired more than 7 days ago (the last week is kept so a returning client is
 *    still told "your session timed out");
 *  - strip sensitive state (transfer EPP/auth codes) from any session not touched for an hour;
 *  - strip the encrypted cPanel password suggestion (pw_suggestion) from any session past its flow expiry;
 *  - purge expired reminder targets and stale, unlocked verification counters.
 */
class CleanupWhatsappSessions extends Command
{
    protected $signature = 'whatsapp:cleanup-sessions {--dry-run}';
    protected $description = 'Purge expired WhatsApp bot sessions and clear sensitive session state (EPP codes older than 1 hour)';

    public function handle(): int
    {
        $dry = (bool) $this->option('dry-run');

        $expired = WhatsappRenewalSession::withoutGlobalScopes()->where('expires_at', '<', now()->subDays(7));
        $expiredCount = (clone $expired)->count();
        if (!$dry) {
            $expired->delete();
        }

        $scrubbed = 0;
        WhatsappRenewalSession::withoutGlobalScopes()
            ->whereNotNull('state')
            ->where('state', 'like', '%auth_info%')
            ->where('updated_at', '<', now()->subHour())
            ->get()
            ->each(function (WhatsappRenewalSession $s) use (&$scrubbed, $dry) {
                $state = $s->state ?? [];
                if (!array_key_exists('auth_info', $state)) {
                    return;
                }
                $scrubbed++;
                if (!$dry) {
                    unset($state['auth_info']);
                    // saveQuietly: keep this a pure scrub (no TTL side effects)
                    $s->forceFill(['state' => $state])->saveQuietly();
                }
            });

        $pw = 0;
        WhatsappRenewalSession::withoutGlobalScopes()
            ->whereNotNull('state')
            ->where('state', 'like', '%pw_suggestion%')
            ->where('expires_at', '<', now())
            ->get()
            ->each(function (WhatsappRenewalSession $s) use (&$pw, $dry) {
                $state = $s->state ?? [];
                if (!array_key_exists('pw_suggestion', $state)) {
                    return;
                }
                $pw++;
                if (!$dry) {
                    unset($state['pw_suggestion']);
                    $s->forceFill(['state' => $state])->saveQuietly();
                }
            });
        if (!$dry) {
            \App\Models\WhatsappOtp::where('created_at', '<', now()->subDay())->delete();
        }

        $targets = WhatsappReminderTarget::where('expires_at', '<', now());
        $targetCount = (clone $targets)->count();
        $attempts = WhatsappVerifyAttempt::where('updated_at', '<', now()->subDays(30))
            ->where(fn ($q) => $q->whereNull('locked_until')->orWhere('locked_until', '<', now()));
        $attemptCount = (clone $attempts)->count();
        if (!$dry) {
            $targets->delete();
            $attempts->delete();
        }

        $this->info(($dry ? '[dry-run] ' : '') . "sessions purged: {$expiredCount}, EPP state scrubbed: {$scrubbed}, password suggestions scrubbed: {$pw}, reminder targets purged: {$targetCount}, verify counters purged: {$attemptCount}");

        return self::SUCCESS;
    }
}
