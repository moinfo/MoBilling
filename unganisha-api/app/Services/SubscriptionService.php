<?php

namespace App\Services;

use App\Models\PlatformSetting;
use App\Models\SubscriptionPlan;
use App\Models\Tenant;
use App\Models\TenantSubscription;
use App\Models\User;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

class SubscriptionService
{
    public function checkout(Tenant $tenant, SubscriptionPlan $plan, User $user, string $paymentMethod = 'pesapal'): array
    {
        $invoiceNumber = TenantSubscription::generateInvoiceNumber();

        $subscription = TenantSubscription::withoutGlobalScopes()->create([
            'tenant_id' => $tenant->id,
            'subscription_plan_id' => $plan->id,
            'user_id' => $user->id,
            'status' => 'pending',
            'amount_paid' => $plan->price,
            'invoice_number' => $invoiceNumber,
            'payment_method' => $paymentMethod,
            'invoice_due_date' => now()->addDays(7),
        ]);

        Log::info('Subscription checkout initiated', [
            'subscription_id' => $subscription->id,
            'tenant_id' => $tenant->id,
            'plan' => $plan->name,
            'payment_method' => $paymentMethod,
            'invoice_number' => $invoiceNumber,
        ]);

        if ($paymentMethod === 'pesapal') {
            return $this->processPesapalCheckout($subscription, $plan, $user);
        }

        // bank_transfer: return subscription details with bank info
        $subscription->load('plan');

        return [
            'subscription_id' => $subscription->id,
            'payment_method' => 'bank_transfer',
            'invoice_number' => $invoiceNumber,
            'invoice_due_date' => $subscription->invoice_due_date->toDateString(),
            'amount' => $plan->price,
            'bank_details' => PlatformSetting::getBankDetails(),
            'redirect_url' => null,
        ];
    }

    private function processPesapalCheckout(TenantSubscription $subscription, SubscriptionPlan $plan, User $user): array
    {
        $merchantRef = 'MOSUB-' . Str::upper(Str::random(8));

        $pesapal = new PesapalService();
        $result = $pesapal->submitOrder(
            $merchantRef,
            (float) $plan->price,
            "MoBilling: {$plan->name} subscription ({$plan->billing_cycle_days} days)",
            [
                'email' => $user->email,
                'phone' => $user->phone ?? '',
                'first_name' => explode(' ', $user->name)[0] ?? '',
                'last_name' => explode(' ', $user->name)[1] ?? '',
            ],
        );

        $subscription->update([
            'order_tracking_id' => $result['order_tracking_id'] ?? null,
            'pesapal_redirect_url' => $result['redirect_url'] ?? null,
        ]);

        return [
            'subscription_id' => $subscription->id,
            'payment_method' => 'pesapal',
            'invoice_number' => $subscription->invoice_number,
            'redirect_url' => $result['redirect_url'] ?? null,
            'order_tracking_id' => $result['order_tracking_id'] ?? null,
        ];
    }

    public function confirmPayment(TenantSubscription $subscription, User $admin, ?string $reference = null): void
    {
        $subscription->update([
            'payment_reference' => $reference ?? $subscription->payment_reference,
            'payment_confirmed_at' => now(),
            'payment_confirmed_by' => $admin->id,
        ]);

        $this->processPaymentCompleted($subscription);

        Log::info('Bank transfer payment confirmed', [
            'subscription_id' => $subscription->id,
            'confirmed_by' => $admin->id,
            'reference' => $reference,
        ]);
    }

    public function uploadPaymentProof(TenantSubscription $subscription, UploadedFile $file): string
    {
        $path = $file->store('payment-proofs', 'public');

        $subscription->update(['payment_proof_path' => $path]);

        Log::info('Payment proof uploaded', [
            'subscription_id' => $subscription->id,
            'path' => $path,
        ]);

        return $path;
    }

    public function processPaymentCompleted(TenantSubscription $subscription): void
    {
        if ($subscription->status !== 'pending') {
            Log::info('Subscription already processed, skipping', ['id' => $subscription->id]);
            return;
        }

        $tenant = Tenant::find($subscription->tenant_id);
        $plan = $subscription->plan;

        // If tenant has an active subscription, extend from its end date
        $existingActive = TenantSubscription::withoutGlobalScopes()
            ->where('tenant_id', $subscription->tenant_id)
            ->where('status', 'active')
            ->where('ends_at', '>', now())
            ->where('id', '!=', $subscription->id)
            ->orderByDesc('ends_at')
            ->first();

        $startsAt = $existingActive ? $existingActive->ends_at : now();
        $endsAt = $startsAt->copy()->addDays($plan->billing_cycle_days);

        $subscription->update([
            'status' => 'active',
            'starts_at' => $startsAt,
            'ends_at' => $endsAt,
            'paid_at' => now(),
        ]);

        // Sync plan permissions to tenant's allowed permissions
        if ($tenant) {
            $planPermissionIds = $plan->permissions()->pluck('permissions.id')->toArray();
            if (!empty($planPermissionIds)) {
                $tenant->allowedPermissions()->syncWithoutDetaching($planPermissionIds);
            }
        }

        Log::info('Subscription activated', [
            'subscription_id' => $subscription->id,
            'tenant' => $tenant?->name,
            'plan' => $plan->name,
            'starts_at' => $startsAt->toDateTimeString(),
            'ends_at' => $endsAt->toDateTimeString(),
        ]);
    }

    public function processPaymentFailed(TenantSubscription $subscription): void
    {
        if ($subscription->status !== 'pending') {
            return;
        }

        $subscription->update(['status' => 'cancelled']);

        Log::info('Subscription payment failed/cancelled', ['id' => $subscription->id]);
    }

    public function expireOverdueSubscriptions(): int
    {
        $count = TenantSubscription::withoutGlobalScopes()
            ->where('status', 'active')
            ->where('ends_at', '<', now())
            ->update(['status' => 'expired']);

        if ($count > 0) {
            Log::info("Expired {$count} overdue subscriptions");
        }

        return $count;
    }
}
