<?php

namespace App\Services;

use App\Models\ClientSubscription;
use App\Models\Document;
use App\Models\RecurringInvoiceLog;
use App\Models\Tenant;
use App\Notifications\SubscriptionReactivatedNotification;
use Illuminate\Support\Facades\Log;

/**
 * When an invoice is paid, activate any linked subscriptions and advance
 * their expire_date one billing cycle. Shared by every payment path
 * (manual recording, Pesapal IPN, credit application).
 */
class SubscriptionActivationService
{
    public function activateFor(Document $document): void
    {
        $logs = RecurringInvoiceLog::withoutGlobalScopes()->where('document_id', $document->id)->get();

        if ($logs->isEmpty()) {
            return;
        }

        $subscriptionIds = $logs->pluck('client_subscription_id')->filter()->unique()->values();
        $fallbackProductIds = $logs->whereNull('client_subscription_id')->pluck('product_service_id')->unique()->values();

        $subscriptions = ClientSubscription::withoutGlobalScopes()
            ->with('productService')
            ->where('client_id', $document->client_id)
            ->whereIn('status', ['pending', 'suspended', 'active'])
            ->where(function ($q) use ($subscriptionIds, $fallbackProductIds) {
                if ($subscriptionIds->isNotEmpty()) {
                    $q->whereIn('id', $subscriptionIds);
                }
                if ($fallbackProductIds->isNotEmpty()) {
                    $q->orWhereIn('product_service_id', $fallbackProductIds);
                }
            })
            ->get();

        $restored = [];

        foreach ($subscriptions as $sub) {
            if ($sub->status === 'suspended') {
                $restored[] = $sub->label ?: ($sub->productService?->name ?? 'service');
            }
            $baseDate = $sub->expire_date ?? $sub->start_date;
            $cycle = $sub->productService?->billing_cycle;

            $newExpireDate = match ($cycle) {
                'monthly' => $baseDate->copy()->addMonth(),
                'quarterly' => $baseDate->copy()->addMonths(3),
                'half_yearly' => $baseDate->copy()->addMonths(6),
                'yearly' => $baseDate->copy()->addYear(),
                default => $baseDate,
            };

            $sub->update([
                'status' => 'active',
                'expire_date' => $newExpireDate,
            ]);
        }

        // Tell the client their suspended service(s) are back (all channels).
        if ($restored) {
            try {
                $client = $document->client()->withoutGlobalScopes()->first();
                $tenant = Tenant::withoutGlobalScopes()->find($document->tenant_id);
                if ($client && $tenant && ($client->email || $client->phone)) {
                    $client->notify(new SubscriptionReactivatedNotification($restored, $tenant));
                }
            } catch (\Throwable $e) {
                Log::warning('Reactivation notification failed', ['error' => $e->getMessage()]);
            }
        }
    }
}
