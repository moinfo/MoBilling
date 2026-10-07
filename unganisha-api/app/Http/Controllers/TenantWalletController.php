<?php

namespace App\Http\Controllers;

use App\Models\TenantWalletTopup;
use App\Models\TenantWalletTransaction;
use App\Services\PesapalService;
use App\Services\TenantWalletService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

/**
 * A white-label reseller tenant's OWN admin managing their OWN prepaid
 * wallet (balance/ledger, top up). Gated by credit.manage — already in the
 * 'reseller' tier permission ceiling (TenantProvisioningService), so every
 * reseller tenant's admin role has it without a new permission. Staff-side
 * "paid outside" confirmation lives on ResellerApplicationController
 * instead (a different trust boundary — Moinfotech's own staff confirming
 * someone else's payment, not self-service).
 */
class TenantWalletController extends Controller
{
    public function show(Request $request)
    {
        $tenant = $request->user()->tenant;

        $ledger = TenantWalletTransaction::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->latest('created_at')->limit(50)->get();

        return response()->json(['data' => [
            'balance'            => (float) $tenant->wallet_balance,
            'is_wallet_gated'    => (bool) $tenant->is_wallet_gated,
            // Wallet top-up pays MoBilling itself, via the PLATFORM's own Pesapal
            // account (config/pesapal.php) — never the tenant's own (that one is
            // for the tenant's OWN clients paying the tenant, a different thing).
            'pesapal_configured' => (bool) (config('pesapal.consumer_key') && config('pesapal.consumer_secret')),
            'ledger'             => $ledger,
        ]]);
    }

    /**
     * Self-service top-up via MoBilling's OWN Pesapal account — this pays US,
     * so it must never go through the tenant's own merchant account (that one
     * collects payments from the tenant's OWN clients, a different payee).
     */
    public function topupPesapal(Request $request)
    {
        $user = $request->user();
        $tenant = $user->tenant;

        if (!$tenant->is_wallet_gated) {
            return response()->json(['message' => 'This tenant does not use the reseller wallet.'], 422);
        }
        if (!(config('pesapal.consumer_key') && config('pesapal.consumer_secret'))) {
            return response()->json(['message' => 'Online top-up is not available right now. Please contact support to top up.'], 422);
        }

        $data = $request->validate(['amount' => 'required|numeric|min:1000']);
        $merchantRef = 'WALLET-' . Str::upper(Str::random(10));

        $topup = TenantWalletTopup::withoutGlobalScopes()->create([
            'tenant_id'     => $tenant->id,
            'requested_by'  => $user->id,
            'amount'        => $data['amount'],
            'status'        => 'pending',
        ]);

        try {
            $pesapal = new PesapalService();
            $result = $pesapal->submitOrder(
                $merchantRef,
                (float) $data['amount'],
                'MoBilling: reseller wallet top-up',
                [
                    'email'      => $user->email,
                    'phone'      => $user->phone ?? '',
                    'first_name' => explode(' ', $user->name)[0] ?? '',
                    'last_name'  => explode(' ', $user->name)[1] ?? '',
                ],
                $tenant->portalUrl('/wallet'),
            );

            $topup->update([
                'order_tracking_id'    => $result['order_tracking_id'] ?? null,
                'pesapal_redirect_url' => $result['redirect_url'] ?? null,
            ]);

            return response()->json([
                'data'    => ['topup_id' => $topup->id, 'redirect_url' => $result['redirect_url'] ?? null],
                'message' => 'Pesapal checkout initiated.',
            ], 201);
        } catch (\Throwable $e) {
            Log::error('Tenant wallet Pesapal top-up failed', ['topup_id' => $topup->id, 'error' => $e->getMessage()]);
            $topup->update(['status' => 'failed']);

            return response()->json(['message' => 'Failed to initiate Pesapal payment. Please try again.'], 500);
        }
    }

    public function topupStatus(Request $request, TenantWalletTopup $topup)
    {
        abort_unless($topup->tenant_id === $request->user()->tenant_id, 404);

        if ($topup->status === 'pending' && $topup->order_tracking_id) {
            try {
                $pesapal = new PesapalService();
                $status = $pesapal->getTransactionStatus($topup->order_tracking_id);
                $topup->update([
                    'payment_status_description' => $status['payment_status_description'] ?? null,
                    'confirmation_code'          => $status['confirmation_code'] ?? $topup->confirmation_code,
                    'payment_method_used'        => $status['payment_method'] ?? $topup->payment_method_used,
                ]);
            } catch (\Throwable $e) {
                Log::warning('Tenant wallet top-up status poll failed', ['topup_id' => $topup->id, 'error' => $e->getMessage()]);
            }
        }

        return response()->json(['data' => $topup->fresh()]);
    }
}
