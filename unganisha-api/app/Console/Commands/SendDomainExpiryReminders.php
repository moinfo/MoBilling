<?php

namespace App\Console\Commands;

use App\Models\Domain;
use App\Models\Tenant;
use App\Notifications\DomainExpiryReminderNotification;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;

/**
 * Warn clients before their domain expires. Manual-renew domains are
 * reminded at 45/30/7/1 days; auto-renew domains only at 7/1 days (their
 * renewal is normally handled by domains:process-renewals — reaching 7
 * days means it failed, e.g. unpaid invoice). Deduped per expiry date via
 * meta.expiry_reminders_sent, so a renewal restarts the cycle cleanly.
 */
class SendDomainExpiryReminders extends Command
{
    protected $signature = 'domains:send-expiry-reminders {--dry-run}';
    protected $description = 'Remind clients about expiring domains (45/30/7/1 days)';

    private const MARKS_MANUAL = [45, 30, 7, 1];
    private const MARKS_AUTO   = [7, 1];

    public function handle(): int
    {
        $dry = (bool) $this->option('dry-run');
        $sent = 0;

        $domains = Domain::withoutGlobalScopes()
            ->whereIn('status', ['active', 'expired'])
            ->whereNotNull('expires_at')
            ->whereNotNull('client_id')
            ->whereBetween('expires_at', [now()->startOfDay(), now()->addDays(45)->endOfDay()])
            ->with(['client' => fn ($q) => $q->withoutGlobalScopes()])
            ->get();

        $tenants = [];

        foreach ($domains as $domain) {
            $client = $domain->client;
            if (!$client || (!$client->email && !$client->phone)) {
                continue;
            }

            $daysLeft = (int) now()->startOfDay()->diffInDays($domain->expires_at->startOfDay());
            $marks = $domain->auto_renew ? self::MARKS_AUTO : self::MARKS_MANUAL;

            // Pick the tightest window that covers today (marks are descending),
            // so a first run at 6 days sends the "7-day" reminder, not the 45-day one.
            $mark = collect($marks)->filter(fn ($m) => $daysLeft <= $m)->last();
            if ($mark === null) {
                continue;
            }

            $expiryKey = $domain->expires_at->toDateString();
            $sentMarks = (array) data_get($domain->meta, "expiry_reminders_sent.{$expiryKey}", []);
            if (in_array($mark, $sentMarks, true)) {
                continue;
            }

            $tenant = $tenants[$domain->tenant_id] ??= Tenant::withoutGlobalScopes()->find($domain->tenant_id);
            if (!$tenant) {
                continue;
            }

            if ($dry) {
                $this->line("[dry] {$domain->name} — {$daysLeft}d left (mark {$mark}) → {$client->name}");
                $sent++;
                continue;
            }

            try {
                $client->notify(new DomainExpiryReminderNotification($domain, $tenant, $daysLeft));
                $meta = $domain->meta ?? [];
                $meta['expiry_reminders_sent'][$expiryKey][] = $mark;
                $domain->update(['meta' => $meta]);
                $sent++;
                $this->info("Reminded: {$domain->name} ({$daysLeft}d left) → {$client->name}");
            } catch (\Throwable $e) {
                Log::warning('Domain expiry reminder failed', ['domain' => $domain->name, 'error' => $e->getMessage()]);
            }
        }

        $this->info(($dry ? 'Dry run: ' : '') . "{$sent} expiry reminder(s).");
        return self::SUCCESS;
    }
}
