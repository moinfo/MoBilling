<?php

namespace App\Http\Controllers;

use App\Models\Document;
use App\Models\ResellerApplication;
use App\Models\TenantWalletTopup;
use App\Models\TenantWalletTransaction;
use App\Services\DocumentNumberService;
use App\Services\PesapalService;
use App\Services\TenantWalletService;
use App\Services\WalletTopupInvoicePdfService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
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

        // Still-pending top-up requests (Pesapal not yet paid, or a Lipa Number
        // invoice awaiting staff confirmation) — these have no ledger row yet
        // (that's only written once the money actually lands), so without this
        // a client-generated invoice would be invisible on the wallet page
        // until someone confirms it days later.
        $pendingTopups = TenantWalletTopup::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->where('status', 'pending')
            ->latest('created_at')->limit(20)->get()
            ->map(fn (TenantWalletTopup $t) => [
                'id'          => $t->id,
                'amount'      => (float) $t->amount,
                'method'      => $t->order_tracking_id ? 'pesapal' : 'lipa_number',
                'reference'   => WalletTopupInvoicePdfService::reference($t),
                'document_id' => $t->document_id,
                'created_at'  => $t->created_at,
            ]);

        return response()->json(['data' => [
            'balance'            => (float) $tenant->wallet_balance,
            'is_wallet_gated'    => (bool) $tenant->is_wallet_gated,
            // Wallet top-up pays MoBilling itself, via the PLATFORM's own Pesapal
            // account (config/pesapal.php) — never the tenant's own (that one is
            // for the tenant's OWN clients paying the tenant, a different thing).
            'pesapal_configured' => (bool) (config('pesapal.consumer_key') && config('pesapal.consumer_secret')),
            'ledger'             => $ledger,
            'pending_topups'     => $pendingTopups,
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

    /**
     * Self-service manual top-up: creates a pending request, a REAL invoice under
     * Moinfotech's own tenant (so it shows up on Moinfotech's own /invoices list,
     * billed to this reseller's own Client record there — a white-label reseller
     * is "linked" to Moinfotech via the wallet, not a normal per-service invoice,
     * so without this the money owed was only ever visible on this isolated wallet
     * screen, never on the books Moinfotech staff actually work from), and hands
     * back a PDF carrying our Lipa Number / bank details + a reference to quote.
     * No online gateway involved — staff mark the invoice paid the normal way
     * (Invoices > record payment), which credits the wallet via DocumentObserver.
     */
    public function topupInvoice(Request $request)
    {
        $user = $request->user();
        $tenant = $user->tenant;

        if (!$tenant->is_wallet_gated) {
            return response()->json(['message' => 'This tenant does not use the reseller wallet.'], 422);
        }

        $platformTenantId = config('portal.storefront_tenant_id');
        $billingClientId = $platformTenantId
            ? ResellerApplication::withoutGlobalScopes()
                ->where('provisioned_tenant_id', $tenant->id)
                ->whereNotNull('client_id')
                ->latest('created_at')->value('client_id')
            : null;

        if (!$platformTenantId || !$billingClientId) {
            return response()->json(['message' => 'Could not find your billing account. Please contact support to top up.'], 422);
        }

        $data = $request->validate(['amount' => 'required|numeric|min:1000']);

        $topup = DB::transaction(function () use ($tenant, $user, $data, $platformTenantId, $billingClientId) {
            $document = Document::withoutGlobalScopes()->create([
                'tenant_id'       => $platformTenantId,
                'client_id'       => $billingClientId,
                'type'            => 'invoice',
                'document_number' => app(DocumentNumberService::class)->generate('invoice', $platformTenantId),
                'date'            => now()->toDateString(),
                'due_date'        => now()->addDays(3)->toDateString(),
                'subtotal'        => $data['amount'],
                'discount_amount' => 0,
                'tax_amount'      => 0,
                'total'           => $data['amount'],
                'status'          => 'sent',
                'notes'           => "Reseller wallet top-up — {$tenant->name}",
                'created_by'      => $user->id,
            ]);

            $document->items()->create([
                'item_type'   => 'service',
                'description' => "Wallet Top-up — {$tenant->name}",
                'quantity'    => 1,
                'price'       => $data['amount'],
                'tax_percent' => 0,
                'tax_amount'  => 0,
                'total'       => $data['amount'],
            ]);

            return TenantWalletTopup::withoutGlobalScopes()->create([
                'tenant_id'    => $tenant->id,
                'requested_by' => $user->id,
                'document_id'  => $document->id,
                'amount'       => $data['amount'],
                'status'       => 'pending',
            ]);
        });

        return response()->json([
            'data'    => ['topup_id' => $topup->id, 'reference' => WalletTopupInvoicePdfService::reference($topup)],
            'message' => 'Invoice generated. Pay via the Lipa Number on the invoice — your wallet is credited once we confirm payment.',
        ], 201);
    }

    public function downloadInvoice(Request $request, TenantWalletTopup $topup)
    {
        abort_unless($topup->tenant_id === $request->user()->tenant_id, 404);

        $pdf = app(WalletTopupInvoicePdfService::class)->generate($topup);

        return $pdf->download(WalletTopupInvoicePdfService::reference($topup) . '.pdf');
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
