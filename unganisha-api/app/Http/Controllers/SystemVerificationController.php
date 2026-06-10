<?php

namespace App\Http\Controllers;

use App\Http\Requests\StoreSystemVerificationRequest;
use App\Http\Requests\StoreSystemVerificationReportRequest;
use App\Http\Resources\SystemVerificationResource;
use App\Http\Resources\SystemVerificationReportResource;
use App\Models\SystemVerification;
use App\Models\SystemVerificationReport;
use App\Models\User;
use App\Notifications\SystemVerificationIssueNotification;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class SystemVerificationController extends Controller
{
    // ── Admin: list / register / update / unregister ───────────────────────

    public function index(Request $request)
    {
        $query = SystemVerification::with(['assignedUser:id,name', 'todaysReport']);

        if ($request->filled('search')) {
            $query->where(function ($q) use ($request) {
                $q->where('name', 'like', '%' . $request->search . '%')
                  ->orWhere('domain_name', 'like', '%' . $request->search . '%')
                  ->orWhere('client_id', 'like', '%' . $request->search . '%');
            });
        }

        return SystemVerificationResource::collection(
            $query->orderBy('name')->paginate($request->per_page ?? 50)
        );
    }

    public function store(StoreSystemVerificationRequest $request)
    {
        $sv = SystemVerification::create($request->validated());
        return new SystemVerificationResource($sv->load('assignedUser', 'todaysReport'));
    }

    public function show(SystemVerification $system_verification)
    {
        return new SystemVerificationResource(
            $system_verification->load('assignedUser', 'todaysReport')
        );
    }

    public function update(StoreSystemVerificationRequest $request, SystemVerification $system_verification)
    {
        $system_verification->update($request->validated());
        return new SystemVerificationResource(
            $system_verification->load('assignedUser', 'todaysReport')
        );
    }

    public function destroy(SystemVerification $system_verification)
    {
        $system_verification->delete();
        return response()->json(['message' => 'Verification system removed']);
    }

    // ── Staff: list MY assigned systems + their today's status ─────────────

    public function mine(Request $request)
    {
        $userId = auth()->id();

        $query = SystemVerification::with('todaysReport')
            ->where('assigned_user_id', $userId)
            ->where('is_active', true);

        return SystemVerificationResource::collection(
            $query->orderBy('name')->get()
        );
    }

    // ── Reports: list all (admin) / submit today's (staff) ─────────────────

    public function listReports(Request $request, SystemVerification $system_verification)
    {
        $query = $system_verification->reports()
            ->with('user:id,name')
            ->orderByDesc('report_date');

        if ($request->filled('date_from')) {
            $query->where('report_date', '>=', $request->date_from);
        }
        if ($request->filled('date_to')) {
            $query->where('report_date', '<=', $request->date_to);
        }

        return SystemVerificationReportResource::collection(
            $query->paginate($request->per_page ?? 50)
        );
    }

    /**
     * Submit today's verification check-in. Idempotent per (system, day):
     * the UNIQUE constraint blocks double-submission; the controller
     * surfaces a friendly 409 instead of a raw SQL exception.
     */
    public function submitReport(StoreSystemVerificationReportRequest $request, SystemVerification $system_verification)
    {
        $userId = auth()->id();

        // Only the assigned staff (or an admin) can submit. The route is
        // permission-gated to system_verification_reports.submit, but we also
        // refuse if it's not actually the assigned person — admins use the
        // admin endpoints to backfill, not this one.
        if ($system_verification->assigned_user_id && $system_verification->assigned_user_id !== $userId) {
            return response()->json([
                'message' => 'This system is assigned to another staff member.',
            ], 403);
        }

        $today = today()->toDateString();
        $existing = $system_verification->reports()->whereDate('report_date', $today)->first();
        if ($existing) {
            return response()->json([
                'message' => "You've already submitted today's report for this system.",
                'data' => new SystemVerificationReportResource($existing),
            ], 409);
        }

        $report = SystemVerificationReport::create([
            'system_verification_id' => $system_verification->id,
            'user_id' => $userId,
            'report_date' => $today,
            'status' => $request->validated('status'),
            'notes' => $request->validated('notes'),
        ]);

        // If they reported an issue, notify every admin in the tenant.
        if ($report->status === 'issue') {
            $this->notifyAdminsOfIssue($report);
        }

        return new SystemVerificationReportResource(
            $report->load('user', 'systemVerification')
        );
    }

    private function notifyAdminsOfIssue(SystemVerificationReport $report): void
    {
        try {
            $tenant = auth()->user()->tenant;
            $admins = User::query()
                ->where('tenant_id', $tenant->id)
                ->whereHas('role', fn ($q) => $q->where('name', 'admin'))
                ->get();

            foreach ($admins as $admin) {
                $admin->notify(new SystemVerificationIssueNotification($tenant, $report));
            }
        } catch (\Throwable $e) {
            // The report is saved; failing to notify shouldn't fail the response.
            Log::error('Failed to notify admins of system verification issue', [
                'report_id' => $report->id,
                'exception' => $e,
            ]);
        }
    }
}
