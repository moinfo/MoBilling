<?php

namespace App\Observers;

use App\Models\Document;
use App\Models\Followup;
use App\Models\PaymentIn;
use App\Models\StaffTarget;
use App\Models\User;
use App\Notifications\InvoicePaymentOnAssignedNotification;
use Illuminate\Support\Facades\Log;

/**
 * Every payment path (PaymentInController, Pesapal webhook, CreditService, imports) creates rows
 * through the PaymentIn model, so a `created` hook is the single convergence point.
 * Runs after the surrounding transaction commits so a rolled-back payment never notifies.
 */
class PaymentInObserver
{
    public bool $afterCommit = true;

    public function created(PaymentIn $payment): void
    {
        try {
            $this->notifyCollectors($payment);
        } catch (\Throwable $e) {
            Log::warning('Collector payment notification failed', ['payment_id' => $payment->id, 'error' => $e->getMessage()]);
        }
    }

    /** Only live, recent payments notify; imports/backfills of history stay silent. */
    private function isLive(PaymentIn $payment): bool
    {
        return !$payment->legacy_id                                              // WHMCS-imported rows
            && $payment->payment_date
            && $payment->payment_date->greaterThanOrEqualTo(now()->subDays(2)->startOfDay())
            && $payment->payment_date->lessThanOrEqualTo(now()->addDay()->endOfDay())
            && $payment->created_at
            && $payment->created_at->greaterThanOrEqualTo(now()->subMinutes(5));
    }

    private function notifyCollectors(PaymentIn $payment): void
    {
        if (!$payment->document_id || (float) $payment->amount <= 0 || !$this->isLive($payment)) {
            return;
        }

        $userIds = Followup::withoutGlobalScopes()
            ->where('document_id', $payment->document_id)
            ->active()
            ->whereNotNull('user_id')
            ->pluck('user_id')->unique();
        if ($userIds->isEmpty()) {
            return;
        }

        $doc = Document::withoutGlobalScopes()->with(['client' => fn ($q) => $q->withoutGlobalScopes()])->find($payment->document_id);
        if (!$doc) {
            return;
        }
        $balance = (float) $doc->balance_due;
        $date = $payment->payment_date;

        foreach (User::withoutGlobalScopes()->whereIn('id', $userIds)->where('is_active', true)->get() as $user) {
            try {
                $tenant = $user->tenant;
                if (!$tenant) {
                    continue;
                }
                $user->notify(new InvoicePaymentOnAssignedNotification(
                    $tenant,
                    $doc->client?->name ?? 'Mteja',
                    $doc->document_number,
                    (float) $payment->amount,
                    $balance,
                    $this->estimateFor($user, $date),
                ));
            } catch (\Throwable $e) {
                Log::warning('Collector payment notification failed', ['user_id' => $user->id, 'error' => $e->getMessage()]);
            }
        }
    }

    /** ESTIMATE only: live collected-to-date vs goal on the user's active 'collections' criterion. */
    private function estimateFor(User $user, $paymentDate): ?array
    {
        $target = StaffTarget::withoutGlobalScopes()
            ->where('tenant_id', $user->tenant_id)
            ->where('user_id', $user->id)
            ->where('status', 'active')
            ->whereDate('period_start', '<=', $paymentDate)
            ->whereDate('period_end', '>=', $paymentDate)
            ->whereHas('criteria', fn ($q) => $q->withoutGlobalScopes()->where('type', 'collections'))
            ->with(['criteria' => fn ($q) => $q->withoutGlobalScopes()->where('type', 'collections')])
            ->first();
        $criterion = $target?->criteria->first();
        if (!$criterion) {
            return null;
        }

        $collected = $target->collectedAmount();
        $goalMet = $collected >= (float) $criterion->goal_value;
        $commission = (clone $criterion)->fill(['verified_value' => $collected, 'goal_met' => $goalMet])->calculateCommission();

        return [
            'target'     => $target->title,
            'collected'  => $collected,
            'goal'       => (float) $criterion->goal_value,
            'commission' => $commission,
        ];
    }
}
