<?php

namespace App\Http\Controllers;

use App\Models\License;
use App\Models\LicensePlan;
use App\Models\LicensePurchase;
use App\Services\PesapalService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

/**
 * Public, unauthenticated checkout for a self-hosted license — the buyer
 * has no MoBilling account. Payment completion (and the only place a
 * License actually gets created) happens in PesapalWebhookController's
 * IPN handler, never here — this only ever registers the order with
 * Pesapal and hands back where to send the browser to pay.
 */
class LicensePurchaseController extends Controller
{
    public function checkout(Request $request)
    {
        $data = $request->validate([
            'customer_name' => 'required|string|max:255',
            'customer_email' => 'required|email|max:255',
            'customer_phone' => 'nullable|string|max:50',
            'product' => 'required|in:lite,reseller,general',
            'billing_period' => 'required|in:monthly,quarterly,semi_annual,annual,perpetual',
        ]);

        $plan = LicensePlan::where('product', $data['product'])->where('is_active', true)->first();
        if (!$plan) {
            return response()->json(['message' => 'This package is not currently available.'], 422);
        }

        $amount = $plan->priceFor($data['billing_period']);
        if ($amount === null) {
            return response()->json(['message' => 'This billing period is not offered for this package.'], 422);
        }

        $purchase = LicensePurchase::create([
            'customer_name' => $data['customer_name'],
            'customer_email' => $data['customer_email'],
            'customer_phone' => $data['customer_phone'] ?? null,
            'product' => $data['product'],
            'billing_period' => $data['billing_period'],
            'amount' => $amount,
            'status' => 'pending',
        ]);

        $nameParts = explode(' ', $data['customer_name'], 2);

        try {
            $pesapal = new PesapalService();
            $result = $pesapal->submitOrder(
                'MOLIC-' . Str::upper(Str::random(8)),
                (float) $amount,
                "MoBilling {$plan->name} License ({$data['billing_period']})",
                [
                    'email' => $data['customer_email'],
                    'phone' => $data['customer_phone'] ?? '',
                    'first_name' => $nameParts[0] ?? '',
                    'last_name' => $nameParts[1] ?? '',
                ],
            );
        } catch (\Throwable $e) {
            Log::error('License purchase: Pesapal order submission failed', [
                'purchase_id' => $purchase->id,
                'error' => $e->getMessage(),
            ]);

            return response()->json(['message' => 'Could not start payment. Please try again shortly.'], 500);
        }

        $purchase->update([
            'order_tracking_id' => $result['order_tracking_id'] ?? null,
            'pesapal_redirect_url' => $result['redirect_url'] ?? null,
        ]);

        Log::info('License purchase checkout initiated', [
            'purchase_id' => $purchase->id,
            'product' => $data['product'],
            'billing_period' => $data['billing_period'],
            'amount' => $amount,
        ]);

        return response()->json([
            'data' => [
                'purchase_id' => $purchase->id,
                'redirect_url' => $result['redirect_url'] ?? null,
                'order_tracking_id' => $result['order_tracking_id'] ?? null,
                'amount' => $amount,
                'product' => $data['product'],
                'billing_period' => $data['billing_period'],
            ],
        ], 201);
    }

    public function status(LicensePurchase $licensePurchase)
    {
        if ($licensePurchase->status === 'pending' && $licensePurchase->order_tracking_id) {
            try {
                $pesapal = new PesapalService();
                $status = $pesapal->getTransactionStatus($licensePurchase->order_tracking_id);

                $licensePurchase->update([
                    'payment_status_description' => $status['payment_status_description'] ?? null,
                    'confirmation_code' => $status['confirmation_code'] ?? $licensePurchase->confirmation_code,
                    'payment_method_used' => $status['payment_method'] ?? $licensePurchase->payment_method_used,
                ]);
            } catch (\Throwable $e) {
                Log::warning('License purchase status poll failed', [
                    'purchase_id' => $licensePurchase->id,
                    'error' => $e->getMessage(),
                ]);
            }
        }

        $license = $licensePurchase->status === 'completed'
            ? License::find($licensePurchase->license_id)
            : null;

        return response()->json([
            'data' => [
                'id' => $licensePurchase->id,
                'status' => $licensePurchase->status,
                'product' => $licensePurchase->product,
                'billing_period' => $licensePurchase->billing_period,
                'amount' => $licensePurchase->amount,
                'license' => $license ? [
                    'license_key' => $license->license_key,
                    'expires_at' => $license->expires_at?->toDateString(),
                ] : null,
            ],
        ]);
    }
}
