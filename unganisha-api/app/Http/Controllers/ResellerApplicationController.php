<?php

namespace App\Http\Controllers;

use App\Models\ResellerApplication;
use App\Notifications\ResellerApplicationDecidedNotification;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Notification;

/**
 * Staff review of white-label reseller applications. Gated by
 * reseller_applications.manage (admin-only, seeded across all three
 * permission layers). Approve is deliberately separate from Provision
 * (Admin\ResellerProvisioningController) — approving just records the
 * decision; provisioning is a second, explicit, reviewable click that
 * actually spins up the new tenant, admin user, infra rows and products.
 * That gives staff a chance to review the fully assembled plan (which
 * categories, what real-cost gaps exist) before committing anything.
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
