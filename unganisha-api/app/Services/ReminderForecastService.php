<?php

namespace App\Services;

use App\Console\Commands\ProcessOverdueInvoices;
use App\Console\Commands\SendDomainExpiryReminders;
use App\Models\ClientSubscription;
use App\Models\Document;
use App\Models\Domain;
use App\Models\RecurringInvoiceLog;
use App\Models\Tenant;
use Carbon\Carbon;

/**
 * Read-only projection of what the reminder cron commands WILL send over the
 * next N days, computed from current data — not a guarantee (a payment,
 * cancellation, or setting change before the date arrives changes the
 * outcome), but lets staff sanity-check the schedule ("who gets warned
 * tomorrow?") without waiting for the real cron to fire.
 *
 * Mirrors the exact selection logic of (and must be kept in sync with):
 *   ProcessOverdueInvoices, SendDomainExpiryReminders,
 *   RecurringInvoiceService::processReminders(), SuspendUnpaidSubscriptions.
 */
class ReminderForecastService
{
    public function forecast(string $tenantId, int $days = 14): array
    {
        $tenant = Tenant::withoutGlobalScopes()->find($tenantId);
        if (!$tenant || !$tenant->hasAccess()) {
            return [];
        }

        $today = Carbon::today();
        $windowEnd = $today->copy()->addDays($days);
        $parallelMode = (bool) config('whmcs.parallel_mode');

        $events = [
            ...$this->overdueInvoiceEvents($tenant, $today, $windowEnd, $parallelMode),
            ...$this->domainExpiryEvents($tenant, $today, $windowEnd),
            ...$this->sslExpiryEvents($tenant, $today, $windowEnd),
            ...$this->recurringInvoiceEvents($tenant, $today, $windowEnd, $parallelMode),
            ...$this->subscriptionSuspensionEvents($tenant, $today, $windowEnd, $parallelMode),
        ];

        usort($events, fn ($a, $b) => $a['date'] <=> $b['date']);

        return $events;
    }

    private function overdueInvoiceEvents(Tenant $tenant, Carbon $today, Carbon $windowEnd, bool $parallelMode): array
    {
        $lateFeeAfterDays = (int) ($tenant->late_fee_days ?? 1);

        $invoices = Document::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->where('type', 'invoice')
            ->when($parallelMode, fn ($q) => $q->whereNull('legacy_id'))
            ->whereNotIn('status', ['paid', 'draft', 'pending_approval', 'cancelled'])
            ->whereNotNull('due_date')
            ->with('client')
            ->get();

        $events = [];

        foreach ($invoices as $doc) {
            $client = $doc->client;
            if (!$client) {
                continue;
            }

            $dueDate = $doc->due_date->copy()->startOfDay();

            [$category, $triggerDate] = match ($doc->overdue_stage) {
                null => $tenant->late_fee_enabled
                    ? ['invoice_late_fee', $dueDate->copy()->addDays($lateFeeAfterDays)]
                    : [null, null],
                'late_fee_applied' => ['invoice_overdue_reminder', $dueDate->copy()->addDays(ProcessOverdueInvoices::REMINDER_STAGE_DAYS)],
                'reminder_7d' => ['invoice_termination_warning', $dueDate->copy()->addDays(ProcessOverdueInvoices::TERMINATION_STAGE_DAYS)],
                default => [null, null], // already at termination_warning — no further auto stage
            };

            if (!$category) {
                continue;
            }

            // Can't have fired before due_date even passed; if the date math
            // lands before today (cron paused, or setting just changed),
            // it'll catch up on the very next run.
            $triggerDate = $triggerDate->lt($today) ? $today->copy() : $triggerDate;
            if ($triggerDate->gt($windowEnd)) {
                continue;
            }

            // invoice_late_fee / invoice_overdue_reminder: mail leg ignores
            // reminder_email_enabled, SMS/WhatsApp legs require it.
            // invoice_termination_warning: all three legs bypass it (final notice).
            $gates = $category === 'invoice_termination_warning'
                ? ['email' => false, 'sms' => false, 'whatsapp' => false]
                : ['email' => false, 'sms' => true, 'whatsapp' => true];

            $events[] = $this->event(
                date: $triggerDate,
                tenant: $tenant,
                client: $client,
                category: $category,
                label: match ($category) {
                    'invoice_late_fee' => "Late fee — {$doc->document_number}",
                    'invoice_overdue_reminder' => "Overdue reminder — {$doc->document_number}",
                    default => "Termination warning — {$doc->document_number}",
                },
                reference: $doc->document_number,
                gates: $gates,
            );
        }

        return $events;
    }

    private function domainExpiryEvents(Tenant $tenant, Carbon $today, Carbon $windowEnd): array
    {
        $domains = Domain::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->whereIn('status', ['active', 'expired'])
            ->whereNotNull('expires_at')
            ->whereNotNull('client_id')
            ->whereBetween('expires_at', [$today, $today->copy()->addDays(45)->endOfDay()])
            ->with(['client' => fn ($q) => $q->withoutGlobalScopes()])
            ->get();

        $events = [];

        foreach ($domains as $domain) {
            $client = $domain->client;
            if (!$client || (!$client->email && !$client->phone)) {
                continue;
            }

            $marks = $domain->auto_renew ? SendDomainExpiryReminders::MARKS_AUTO : SendDomainExpiryReminders::MARKS_MANUAL;
            $expiryKey = $domain->expires_at->toDateString();
            $sentMarks = (array) data_get($domain->meta, "expiry_reminders_sent.{$expiryKey}", []);

            // The real command fires only the tightest un-sent mark that's
            // already due on any given day — a looser mark whose window
            // already passed without firing is permanently skipped, not
            // caught up later. So: at most one "catch-up" event for today
            // (the tightest overdue mark), then each remaining mark's own
            // future date — those are never shadowed since they strictly
            // decrease as marks shrink.
            $overdueMarks = [];
            foreach ($marks as $mark) {
                if (in_array($mark, $sentMarks, true)) {
                    continue;
                }
                $naturalDate = $domain->expires_at->copy()->startOfDay()->subDays($mark);
                if ($naturalDate->lte($today)) {
                    $overdueMarks[] = $mark;
                    continue;
                }
                if ($naturalDate->gt($windowEnd)) {
                    continue;
                }

                $events[] = $this->event(
                    date: $naturalDate,
                    tenant: $tenant,
                    client: $client,
                    category: 'domain_expiry',
                    label: "Domain expiry ({$mark}d) — {$domain->name}",
                    reference: $domain->name,
                );
            }

            if ($overdueMarks) {
                $tightest = min($overdueMarks);
                $events[] = $this->event(
                    date: $today,
                    tenant: $tenant,
                    client: $client,
                    category: 'domain_expiry',
                    label: "Domain expiry ({$tightest}d) — {$domain->name}",
                    reference: $domain->name,
                );
            }
        }

        return $events;
    }

    private function sslExpiryEvents(Tenant $tenant, Carbon $today, Carbon $windowEnd): array
    {
        $domains = Domain::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->where('status', 'active')
            ->whereNotNull('client_id')
            ->where('meta->ssl_expires_at', '!=', null)
            ->with(['client' => fn ($q) => $q->withoutGlobalScopes()])
            ->get();

        $events = [];

        foreach ($domains as $domain) {
            $expires = data_get($domain->meta, 'ssl_expires_at');
            $client = $domain->client;
            if (!$expires || !$client || !$client->email) {
                continue;
            }

            $expiresAt = Carbon::parse($expires)->startOfDay();
            if ($expiresAt->isPast()) {
                continue;
            }

            $sentMarks = (array) data_get($domain->meta, "ssl_reminders_sent.{$expires}", []);

            // Same "tightest overdue mark only" rule as domain_expiry above.
            $overdueMarks = [];
            foreach (SendDomainExpiryReminders::MARKS_SSL as $mark) {
                if (in_array($mark, $sentMarks, true)) {
                    continue;
                }
                $naturalDate = $expiresAt->copy()->subDays($mark);
                if ($naturalDate->lte($today)) {
                    $overdueMarks[] = $mark;
                    continue;
                }
                if ($naturalDate->gt($windowEnd)) {
                    continue;
                }

                $events[] = $this->event(
                    date: $naturalDate,
                    tenant: $tenant,
                    client: $client,
                    category: 'ssl_expiry',
                    label: "SSL expiry ({$mark}d) — {$domain->name}",
                    reference: $domain->name,
                    smsCapable: false,
                    whatsappCapable: false,
                );
            }

            if ($overdueMarks) {
                $tightest = min($overdueMarks);
                $events[] = $this->event(
                    date: $today,
                    tenant: $tenant,
                    client: $client,
                    category: 'ssl_expiry',
                    label: "SSL expiry ({$tightest}d) — {$domain->name}",
                    reference: $domain->name,
                    smsCapable: false,
                    whatsappCapable: false,
                );
            }
        }

        return $events;
    }

    private function recurringInvoiceEvents(Tenant $tenant, Carbon $today, Carbon $windowEnd, bool $parallelMode): array
    {
        $logs = RecurringInvoiceLog::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->whereNotNull('document_id')
            ->whereNotNull('invoice_created_at')
            ->when($parallelMode, fn ($q) => $q->whereHas('document', fn ($d) => $d->whereNull('legacy_id')))
            ->with(['document', 'client' => fn ($q) => $q->withoutGlobalScopes()])
            ->get()
            ->unique('document_id');

        $events = [];

        foreach ($logs as $log) {
            $document = $log->document;
            $client = $log->client;
            if (!$document || $document->status === 'paid' || !$client) {
                continue;
            }

            $alreadySent = $log->reminders_sent ?? [];

            foreach (\App\Services\RecurringInvoiceService::REMINDER_DAYS as $offset) {
                if (in_array($offset, $alreadySent, true)) {
                    continue;
                }
                $triggerDate = $log->next_bill_date->copy()->startOfDay()->subDays($offset);
                if ($triggerDate->lt($today) || $triggerDate->gt($windowEnd)) {
                    continue;
                }

                $events[] = $this->event(
                    date: $triggerDate,
                    tenant: $tenant,
                    client: $client,
                    category: 'recurring_invoice_reminder',
                    label: "Renewal reminder ({$offset}d) — {$document->document_number}",
                    reference: $document->document_number,
                );
            }
        }

        return $events;
    }

    private function subscriptionSuspensionEvents(Tenant $tenant, Carbon $today, Carbon $windowEnd, bool $parallelMode): array
    {
        if (!$tenant->auto_suspend_enabled) {
            return [];
        }

        $graceDays = (int) ($tenant->subscription_grace_days ?? 7);
        $featureLaunch = Carbon::parse('2026-03-01');

        $subscriptions = ClientSubscription::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->whereNull('deleted_at')
            ->when($parallelMode, fn ($q) => $q->whereNull('legacy_id'))
            ->where('status', 'active')
            ->with(['client' => fn ($q) => $q->withoutGlobalScopes()])
            ->get();

        if ($subscriptions->isEmpty()) {
            return [];
        }

        $latestLogMap = RecurringInvoiceLog::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->whereNotNull('document_id')
            ->whereNotNull('client_subscription_id')
            ->with('document')
            ->orderByDesc('invoice_created_at')
            ->get()
            ->unique('client_subscription_id')
            ->keyBy('client_subscription_id');

        $events = [];

        foreach ($subscriptions as $subscription) {
            $client = $subscription->client;
            $log = $latestLogMap->get($subscription->id);
            if (!$client || !$log || !$log->document) {
                continue;
            }

            $document = $log->document;
            $isUnpaid = !in_array($document->status, ['paid', 'draft']);
            $dueDate = $document->due_date;
            if (!$isUnpaid || !$dueDate) {
                continue;
            }

            $effectiveStart = $dueDate->greaterThan($featureLaunch) ? $dueDate : $featureLaunch;
            $graceCutoff = $effectiveStart->copy()->addDays($graceDays);
            $triggerDate = $graceCutoff->copy()->addDay()->startOfDay();
            $triggerDate = $triggerDate->lt($today) ? $today->copy() : $triggerDate;
            if ($triggerDate->gt($windowEnd)) {
                continue;
            }

            $events[] = $this->event(
                date: $triggerDate,
                tenant: $tenant,
                client: $client,
                category: 'subscription_suspension',
                label: "Suspension — {$subscription->label}",
                reference: $subscription->label,
                gates: ['email' => false, 'sms' => false, 'whatsapp' => false],
            );
        }

        return $events;
    }

    /**
     * $gates controls, per channel, whether the notification's via() also
     * requires the reminder_{channel}_enabled sub-toggle — this is genuinely
     * asymmetric per notification class in the real code (e.g. the late-fee
     * and overdue-reminder mail leg ignores reminder_email_enabled while
     * their SMS/WhatsApp legs require it), so it must be passed explicitly
     * per category rather than assumed uniform.
     */
    private function event(
        Carbon $date,
        Tenant $tenant,
        $client,
        string $category,
        string $label,
        string $reference,
        array $gates = ['email' => true, 'sms' => true, 'whatsapp' => true],
        bool $smsCapable = true,
        bool $whatsappCapable = true,
    ): array {
        $channels = [
            'email' => (bool) $tenant->email_enabled && (!$gates['email'] || $tenant->reminder_email_enabled) && (bool) $client->email,
            'sms' => $smsCapable && (bool) $tenant->sms_enabled && (!$gates['sms'] || $tenant->reminder_sms_enabled) && (bool) $client->phone,
            'whatsapp' => $whatsappCapable && (bool) $tenant->whatsapp_enabled && (!$gates['whatsapp'] || $tenant->reminder_whatsapp_enabled) && (bool) $client->phone,
        ];

        return [
            'date' => $date->toDateString(),
            'client_id' => $client->id,
            'client_name' => $client->name,
            'category' => $category,
            'label' => $label,
            'reference' => $reference,
            'channels' => array_keys(array_filter($channels)),
            'recipient_email' => $client->email,
            'recipient_phone' => $client->phone,
        ];
    }
}
