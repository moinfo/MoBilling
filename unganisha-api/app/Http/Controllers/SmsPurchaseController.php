<?php

namespace App\Http\Controllers;

use App\Models\SmsPackage;
use App\Models\SmsPurchase;
use App\Models\User;
use App\Notifications\SmsActivationRequestNotification;
use App\Services\PesapalService;
use App\Services\ResellerService;
use App\Services\SmsPurchasePdfService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

class SmsPurchaseController extends Controller
{
    public function packages()
    {
        return response()->json([
            'data' => SmsPackage::active()->ordered()->get(),
        ]);
    }

    public function balance()
    {
        $tenant = auth()->user()->tenant;

        if (!$tenant->sms_enabled || !$tenant->sms_authorization) {
            return response()->json([
                'data' => ['sms_balance' => null, 'message' => 'SMS not configured for this tenant.'],
            ]);
        }

        try {
            $reseller = new ResellerService();
            $result = $reseller->getBalance($tenant);

            return response()->json([
                'data' => [
                    'sms_balance' => $result['data']['sms_balance'] ?? $result['sms_balance'] ?? 0,
                ],
            ]);
        } catch (\Throwable $e) {
            return response()->json([
                'data' => ['sms_balance' => null, 'error' => $e->getMessage()],
            ]);
        }
    }

    public function checkout(Request $request)
    {
        $data = $request->validate([
            'sms_quantity' => 'required|integer|min:100',
        ]);

        $package = SmsPackage::forQuantity($data['sms_quantity']);

        if (!$package) {
            return response()->json(['message' => 'No matching package found for the given quantity.'], 422);
        }

        $totalAmount = $data['sms_quantity'] * $package->price_per_sms;
        $merchantRef = 'MOBILL-' . Str::upper(Str::random(8));

        $purchase = SmsPurchase::create([
            'user_id' => auth()->id(),
            'sms_quantity' => $data['sms_quantity'],
            'price_per_sms' => $package->price_per_sms,
            'total_amount' => $totalAmount,
            'package_name' => $package->name,
        ]);

        $user = auth()->user();

        try {
            $pesapal = new PesapalService();
            $result = $pesapal->submitOrder(
                $merchantRef,
                $totalAmount,
                "MoBilling: {$data['sms_quantity']} SMS credits",
                [
                    'email' => $user->email,
                    'phone' => $user->phone ?? '',
                    'first_name' => explode(' ', $user->name)[0] ?? '',
                    'last_name' => explode(' ', $user->name)[1] ?? '',
                ],
            );

            $purchase->update([
                'order_tracking_id' => $result['order_tracking_id'] ?? null,
                'pesapal_redirect_url' => $result['redirect_url'] ?? null,
            ]);

            Log::info('Pesapal checkout initiated', [
                'purchase_id' => $purchase->id,
                'merchant_ref' => $merchantRef,
                'order_tracking_id' => $result['order_tracking_id'] ?? null,
            ]);

            return response()->json([
                'message' => 'Pesapal checkout initiated.',
                'data' => [
                    'purchase_id' => $purchase->id,
                    'redirect_url' => $result['redirect_url'] ?? null,
                    'order_tracking_id' => $result['order_tracking_id'] ?? null,
                ],
            ], 201);
        } catch (\Throwable $e) {
            Log::error('Pesapal checkout failed', [
                'purchase_id' => $purchase->id,
                'error' => $e->getMessage(),
            ]);

            $purchase->update(['status' => 'failed']);

            return response()->json([
                'message' => 'Failed to initiate Pesapal payment. Please try again.',
            ], 500);
        }
    }

    public function checkStatus(SmsPurchase $smsPurchase)
    {
        if ($smsPurchase->status === 'pending' && $smsPurchase->order_tracking_id) {
            try {
                $pesapal = new PesapalService();
                $status = $pesapal->getTransactionStatus($smsPurchase->order_tracking_id);

                $smsPurchase->update([
                    'payment_status_description' => $status['payment_status_description'] ?? null,
                    'confirmation_code' => $status['confirmation_code'] ?? $smsPurchase->confirmation_code,
                    'payment_method_used' => $status['payment_method'] ?? $smsPurchase->payment_method_used,
                ]);
            } catch (\Throwable $e) {
                Log::warning('Pesapal status poll failed', [
                    'purchase_id' => $smsPurchase->id,
                    'error' => $e->getMessage(),
                ]);
            }
        }

        return response()->json([
            'data' => [
                'id' => $smsPurchase->id,
                'status' => $smsPurchase->status,
                'payment_status_description' => $smsPurchase->payment_status_description,
                'confirmation_code' => $smsPurchase->confirmation_code,
                'sms_quantity' => $smsPurchase->sms_quantity,
                'total_amount' => $smsPurchase->total_amount,
            ],
        ]);
    }

    public function history()
    {
        $purchases = SmsPurchase::latest()->paginate(20);

        return response()->json($purchases);
    }

    public function requestActivation()
    {
        $tenant = auth()->user()->tenant;

        if ($tenant->sms_enabled && $tenant->sms_authorization) {
            return response()->json(['message' => 'SMS is already configured for your account.'], 422);
        }

        $superAdmins = User::where('role', 'super_admin')->get();

        foreach ($superAdmins as $admin) {
            $admin->notify(new SmsActivationRequestNotification($tenant));
        }

        return response()->json(['message' => 'Your request has been sent to the administrator.']);
    }

    public function retryPayment(SmsPurchase $smsPurchase)
    {
        if ($smsPurchase->status === 'completed') {
            return response()->json(['message' => 'This purchase is already completed.'], 422);
        }

        // If a redirect URL already exists, return it
        if ($smsPurchase->pesapal_redirect_url) {
            return response()->json([
                'data' => ['redirect_url' => $smsPurchase->pesapal_redirect_url],
            ]);
        }

        // Re-submit to Pesapal
        $user = auth()->user();
        $merchantRef = 'MOBILL-' . Str::upper(Str::random(8));

        try {
            $pesapal = new PesapalService();
            $result = $pesapal->submitOrder(
                $merchantRef,
                $smsPurchase->total_amount,
                "MoBilling: {$smsPurchase->sms_quantity} SMS credits",
                [
                    'email' => $user->email,
                    'phone' => $user->phone ?? '',
                    'first_name' => explode(' ', $user->name)[0] ?? '',
                    'last_name' => explode(' ', $user->name)[1] ?? '',
                ],
            );

            $smsPurchase->update([
                'status' => 'pending',
                'order_tracking_id' => $result['order_tracking_id'] ?? null,
                'pesapal_redirect_url' => $result['redirect_url'] ?? null,
            ]);

            return response()->json([
                'data' => ['redirect_url' => $result['redirect_url'] ?? null],
            ]);
        } catch (\Throwable $e) {
            Log::error('Pesapal retry failed', [
                'purchase_id' => $smsPurchase->id,
                'error' => $e->getMessage(),
            ]);

            return response()->json([
                'message' => 'Failed to initiate payment. Please try again.',
            ], 500);
        }
    }

    public function downloadReceipt(SmsPurchase $smsPurchase)
    {
        if ($smsPurchase->status !== 'completed') {
            return response()->json(['message' => 'Receipt is only available for completed purchases.'], 422);
        }

        $pdfService = new SmsPurchasePdfService();
        $pdf = $pdfService->generateReceipt($smsPurchase);

        return $pdf->download("sms-receipt-{$smsPurchase->receipt_number}.pdf");
    }

    public function downloadInvoice(SmsPurchase $smsPurchase)
    {
        $pdfService = new SmsPurchasePdfService();
        $pdf = $pdfService->generateInvoice($smsPurchase);

        return $pdf->download("sms-invoice-{$smsPurchase->id}.pdf");
    }
}
