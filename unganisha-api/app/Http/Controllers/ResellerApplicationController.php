<?php

namespace App\Http\Controllers;

use App\Models\ResellerApplication;
use App\Models\TenantWalletTopup;
use App\Notifications\ResellerApplicationDecidedNotification;
use App\Services\ResellerProvisioningService;
use App\Services\WalletTopupInvoicePdfService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Notification;

/**
 * Staff review of white-label reseller applications. Gated by
 * reseller_applications.manage (admin-only, seeded across all three
 * permission layers). Approve is deliberately separate from Provision
 * (provisionPreview/provision below, backed by ResellerProvisioningService)
 * — approving just records the decision; provisioning is a second, explicit,
 * reviewable click that actually spins up the new tenant, admin user, infra
 * rows and products. That gives staff a chance to review the fully assembled
 * plan (which categories, what real-cost gaps exist) before committing
 * anything. Also carries staff-confirmed "paid outside" wallet top-ups for
 * a provisioned reseller tenant (walletShow/walletTopup) — a different
 * trust boundary than the reseller's own self-service Pesapal top-up
 * (TenantWalletController), so it stays on the same admin-only permission
 * as approve/reject/provision rather than the reseller's own credit.manage.
 */
class ResellerApplicationController extends Controller
{
    public function index(Request $request)
    {
        $tenantId = $request->user()->tenant_id;

        $query = ResellerApplication::withoutGlobalScopes()
            ->where('tenant_id', $tenantId)
            ->with(['client:id,name,email,phone', 'decidedBy:id,name', 'provisionedTenant:id,name,custom_domain']);

        if ($status = $request->input('status')) {
            $query->where('status', $status);
        }

        $applications = $query->latest('created_at')->paginate($request->input('per_page', 20));

        return response()->json($applications);
    }

    public function show(Request $request, ResellerApplication $resellerApplication)
    {
        $this->authorizeTenant($request, $resellerApplication);
        $resellerApplication->load(['client', 'decidedBy:id,name', 'provisionedTenant:id,name,custom_domain']);

        return response()->json(['data' => $resellerApplication]);
    }

    private function authorizeTenant(Request $request, ResellerApplication $application): void
    {
        abort_unless($application->tenant_id === $request->user()->tenant_id, 404);
    }

    public function approve(Request $request, ResellerApplication $resellerApplication)
    {
        $this->authorizeTenant($request, $resellerApplication);

        if ($resellerApplication->status !== 'pending') {
            return response()->json(['message' => 'Only a pending application can be approved.'], 422);
        }

        $data = $request->validate(['staff_note' => 'nullable|string|max:2000']);

        $resellerApplication->update([
            'status'      => 'approved',
            'staff_note'  => $data['staff_note'] ?? $resellerApplication->staff_note,
            'decided_by'  => $request->user()->id,
            'decided_at'  => now(),
        ]);

        $this->notifyClient($resellerApplication);

        return response()->json(['data' => $resellerApplication->fresh(), 'message' => 'Application approved. Provision the tenant when ready.']);
    }

    public function reject(Request $request, ResellerApplication $resellerApplication)
    {
        $this->authorizeTenant($request, $resellerApplication);

        if ($resellerApplication->status !== 'pending') {
            return response()->json(['message' => 'Only a pending application can be rejected.'], 422);
        }

        $data = $request->validate(['staff_note' => 'required|string|max:2000']);

        $resellerApplication->update([
            'status'      => 'rejected',
            'staff_note'  => $data['staff_note'],
            'decided_by'  => $request->user()->id,
            'decided_at'  => now(),
        ]);

        $this->notifyClient($resellerApplication);

        return response()->json(['data' => $resellerApplication->fresh(), 'message' => 'Application rejected.']);
    }

    public function provisionPreview(Request $request, ResellerApplication $resellerApplication, ResellerProvisioningService $service)
    {
        $this->authorizeTenant($request, $resellerApplication);

        if ($resellerApplication->status !== 'approved') {
            return response()->json(['message' => 'Only an approved application can be previewed for provisioning.'], 422);
        }

        return response()->json(['data' => $service->preview($resellerApplication)]);
    }

    public function provision(Request $request, ResellerApplication $resellerApplication, ResellerProvisioningService $service)
    {
        $this->authorizeTenant($request, $resellerApplication);

        try {
            [$tenant, $adminUser] = $service->provision($resellerApplication, $request->user());
        } catch (\RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        } catch (\Illuminate\Database\QueryException $e) {
            report($e);
            return response()->json(['message' => 'Could not provision — a value collided with an existing record (e.g. the admin email is already used by a staff account). Nothing was created.'], 422);
        }

        return response()->json([
            'data' => [
                'tenant_id'      => $tenant->id,
                'tenant_name'    => $tenant->name,
                'custom_domain'  => $tenant->custom_domain,
                'admin_email'    => $adminUser->email,
            ],
            'message' => "Reseller tenant \"{$tenant->name}\" provisioned. Tell the reseller admin ({$adminUser->email}) to use \"Forgot password\" on the login page to set their own password.",
        ], 201);
    }

    /** Staff view of a provisioned reseller tenant's wallet — balance + recent ledger. */
    public function walletShow(Request $request, ResellerApplication $resellerApplication)
    {
        $this->authorizeTenant($request, $resellerApplication);

        if (!$resellerApplication->provisioned_tenant_id) {
            return response()->json(['message' => 'This application has not been provisioned yet.'], 422);
        }

        $tenant = \App\Models\Tenant::withoutGlobalScopes()->findOrFail($resellerApplication->provisioned_tenant_id);
        $ledger = \App\Models\TenantWalletTransaction::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)->latest('created_at')->limit(50)->get();

        // Pending top-up requests this reseller has already generated (a self-service
        // "Pay via Lipa Number" invoice, or an unpaid Pesapal attempt) — staff need to
        // see these to know there's a manual payment to go confirm, not just the
        // ledger of what's already settled.
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
            'balance'        => (float) $tenant->wallet_balance,
            'ledger'         => $ledger,
            'pending_topups' => $pendingTopups,
        ]]);
    }

    /** Staff-confirmed "paid outside" top-up — same audit rigor as OfflinePaymentService (amount, reference, notes, who). */
    public function walletTopup(Request $request, ResellerApplication $resellerApplication, \App\Services\TenantWalletService $wallet)
    {
        $this->authorizeTenant($request, $resellerApplication);

        if (!$resellerApplication->provisioned_tenant_id) {
            return response()->json(['message' => 'This application has not been provisioned yet.'], 422);
        }

        $data = $request->validate([
            'amount'    => 'required|numeric|min:1',
            'reference' => 'nullable|string|max:255',
            'notes'     => 'nullable|string|max:2000',
            'topup_id'  => 'nullable|uuid',
        ]);

        $tenant = \App\Models\Tenant::withoutGlobalScopes()->findOrFail($resellerApplication->provisioned_tenant_id);

        // Confirming a specific pending invoice (self-service Lipa Number/Pesapal
        // request) rather than an ad hoc "paid outside" entry — close it out so it
        // stops showing as pending everywhere it's surfaced.
        $topup = null;
        if (!empty($data['topup_id'])) {
            $topup = TenantWalletTopup::withoutGlobalScopes()
                ->where('id', $data['topup_id'])
                ->where('tenant_id', $tenant->id)
                ->where('status', 'pending')
                ->first();
            if (!$topup) {
                return response()->json(['message' => 'That pending top-up was not found or is no longer pending.'], 422);
            }
            // Has a real invoice under Moinfotech's own tenant (see TenantWalletController::
            // topupInvoice) — record the payment there instead (Invoices > record payment),
            // which recomputes the invoice's own status correctly (sent/partial/paid) and
            // credits the wallet via DocumentObserver. Confirming it here instead would
            // credit the wallet but leave that invoice looking permanently unpaid.
            if ($topup->document_id) {
                return response()->json(['message' => 'This top-up has its own invoice — record the payment on that invoice (Invoices page) instead of confirming it here.'], 422);
            }
        }

        $newBalance = $wallet->topUp(
            $tenant,
            (float) $data['amount'],
            $data['reference'] ?? $topup?->id,
            'Paid outside, confirmed by staff. ' . ($data['notes'] ?? ''),
            $request->user()->id,
        );

        $topup?->update(['status' => 'completed', 'completed_at' => now(), 'payment_method_used' => $topup->order_tracking_id ? 'pesapal' : 'lipa_number']);

        return response()->json(['data' => ['balance' => $newBalance], 'message' => 'Wallet topped up.']);
    }

    private function notifyClient(ResellerApplication $application): void
    {
        try {
            $client = \App\Models\Client::withoutGlobalScopes()->find($application->client_id);
            if ($client && ($client->email || $client->phone)) {
                Notification::send($client, new ResellerApplicationDecidedNotification($application));
            }
        } catch (\Throwable $e) {
            report($e);
        }
    }
}
