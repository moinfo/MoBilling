<?php

namespace App\Http\Controllers;

use App\Models\SubscriptionPlan;
use App\Models\TenantSubscription;
use App\Services\PesapalService;
use App\Services\SubscriptionInvoicePdfService;
use App\Services\SubscriptionService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class SubscriptionController extends Controller
{
    public function plans(): JsonResponse
    {
        return response()->json([
            'data' => SubscriptionPlan::active()->ordered()->get(),
        ]);
    }

    public function current(): JsonResponse
    {
        $user = auth()->user();
        $tenant = $user->tenant;

        if (!$tenant) {
            return response()->json(['message' => 'No tenant found'], 404);
        }

        $tenant->load('activeSubscription.plan');

        return response()->json([
            'data' => [
                'subscription_status' => $tenant->subscriptionStatus(),
                'days_remaining' => $tenant->daysRemaining(),
                'trial_ends_at' => $tenant->trial_ends_at,
                'active_subscription' => $tenant->activeSubscription,
            ],
        ]);
    }

    public function checkout(Request $request): JsonResponse
    {
        $request->validate([
            'plan_id' => 'required|uuid|exists:subscription_plans,id',
            'payment_method' => 'sometimes|in:pesapal,bank_transfer',
        ]);

        $user = auth()->user();
        $tenant = $user->tenant;

        if (!$tenant) {
            return response()->json(['message' => 'No tenant found'], 404);
        }

        $plan = SubscriptionPlan::findOrFail($request->plan_id);

        if (!$plan->is_active) {
            return response()->json(['message' => 'This plan is no longer available.'], 422);
        }

        try {
            $service = new SubscriptionService();
            $paymentMethod = $request->input('payment_method', 'pesapal');
            $result = $service->checkout($tenant, $plan, $user, $paymentMethod);

            return response()->json([
                'message' => $paymentMethod === 'bank_transfer'
                    ? 'Invoice generated. Please pay via bank transfer.'
                    : 'Subscription checkout initiated.',
                'data' => $result,
            ], 201);
        } catch (\Throwable $e) {
            Log::error('Subscription checkout failed', [
                'tenant_id' => $tenant->id,
                'plan_id' => $plan->id,
                'error' => $e->getMessage(),
            ]);

            return response()->json([
                'message' => 'Failed to initiate payment. Please try again.',
            ], 500);
        }
    }

    public function history(): JsonResponse
    {
        $subscriptions = TenantSubscription::with('plan')
            ->latest()
            ->paginate(20);

        return response()->json($subscriptions);
    }

    public function status(TenantSubscription $tenantSubscription): JsonResponse
    {
        if ($tenantSubscription->status === 'pending' && $tenantSubscription->order_tracking_id) {
            try {
                $pesapal = new PesapalService();
                $status = $pesapal->getTransactionStatus($tenantSubscription->order_tracking_id);

                $tenantSubscription->update([
                    'payment_status_description' => $status['payment_status_description'] ?? null,
                    'confirmation_code' => $status['confirmation_code'] ?? $tenantSubscription->confirmation_code,
                    'payment_method_used' => $status['payment_method'] ?? $tenantSubscription->payment_method_used,
                ]);
            } catch (\Throwable $e) {
                Log::warning('Subscription status poll failed', [
                    'subscription_id' => $tenantSubscription->id,
                    'error' => $e->getMessage(),
                ]);
            }
        }

        return response()->json([
            'data' => [
                'id' => $tenantSubscription->id,
                'status' => $tenantSubscription->status,
                'payment_status_description' => $tenantSubscription->payment_status_description,
                'confirmation_code' => $tenantSubscription->confirmation_code,
                'plan' => $tenantSubscription->plan,
                'amount_paid' => $tenantSubscription->amount_paid,
                'starts_at' => $tenantSubscription->starts_at,
                'ends_at' => $tenantSubscription->ends_at,
                'invoice_number' => $tenantSubscription->invoice_number,
                'payment_method' => $tenantSubscription->payment_method,
                'invoice_due_date' => $tenantSubscription->invoice_due_date,
                'payment_proof_path' => $tenantSubscription->payment_proof_path,
                'payment_confirmed_at' => $tenantSubscription->payment_confirmed_at,
            ],
        ]);
    }

    public function downloadInvoice(TenantSubscription $tenantSubscription): mixed
    {
        $user = auth()->user();

        // Ensure the user belongs to the subscription's tenant
        if ($user->tenant_id !== $tenantSubscription->tenant_id && !$user->isSuperAdmin()) {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        $pdfService = new SubscriptionInvoicePdfService();
        $pdf = $pdfService->generate($tenantSubscription);

        return $pdf->download("invoice-{$tenantSubscription->invoice_number}.pdf");
    }

    public function uploadProof(Request $request, TenantSubscription $tenantSubscription): JsonResponse
    {
        $request->validate([
            'proof' => 'required|file|mimes:pdf,jpg,jpeg,png|max:5120',
        ]);

        $user = auth()->user();

        if ($user->tenant_id !== $tenantSubscription->tenant_id) {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        if ($tenantSubscription->status !== 'pending') {
            return response()->json(['message' => 'This subscription is not pending payment.'], 422);
        }

        $service = new SubscriptionService();
        $path = $service->uploadPaymentProof($tenantSubscription, $request->file('proof'));

        return response()->json([
            'message' => 'Payment proof uploaded successfully.',
            'data' => ['payment_proof_path' => $path],
        ]);
    }
}
