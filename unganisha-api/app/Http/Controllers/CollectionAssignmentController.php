<?php

namespace App\Http\Controllers;

use App\Models\CollectionAssignment;
use App\Traits\AuthorizesPermissions;
use Illuminate\Http\Request;

class CollectionAssignmentController extends Controller
{
    use AuthorizesPermissions;

    private function isAdmin($user): bool
    {
        return $user->hasPermission('staff_targets.manage')
            || $user->hasPermission('staff_targets.verify')
            || $user->hasPermission('staff_reports.view_all');
    }

    /** Rows with live progress + totals. Non-admins (or mine=1) only ever see their own. */
    public function index(Request $request)
    {
        $user = auth()->user();
        $q = CollectionAssignment::with([
            'user:id,name',
            'document' => fn ($d) => $d->withSum('payments', 'amount')->withSum('refunds', 'amount')->with('client:id,name'),
        ])->orderByDesc('created_at');

        if (!$this->isAdmin($user) || $request->boolean('mine')) {
            $q->where('user_id', $user->id);
        } elseif ($request->filled('user_id')) {
            $q->where('user_id', $request->user_id);
        }
        if ($request->filled('status') && $request->status !== 'all') {
            $q->where('status', $request->status);
        }
        if ($request->filled('date_from')) {
            $q->whereDate('created_at', '>=', $request->date_from);
        }
        if ($request->filled('date_to')) {
            $q->whereDate('created_at', '<=', $request->date_to);
        }
        if ($request->filled('payout') && in_array($request->payout, ['paid', 'unpaid'], true)) {
            $request->payout === 'paid' ? $q->whereNotNull('paid_out_at') : $q->whereNull('paid_out_at');
        }

        $totals = ['target' => 0.0, 'collected' => 0.0, 'commission_earned' => 0.0, 'commission_unpaid' => 0.0, 'count' => 0];
        $rows = $q->get()->map(function (CollectionAssignment $a) use (&$totals) {
            $doc = $a->document;
            $p = $a->progress($doc ? (float) $doc->paid_amount : null);
            $totals['count']++;
            if ($a->status !== 'cancelled') {
                $totals['target'] += $p['target'];
                $totals['collected'] += $p['collected'];
                $totals['commission_earned'] += $p['commission_earned'];
                if (!$a->paid_out_at) {
                    $totals['commission_unpaid'] += $p['commission_earned'];
                }
            }

            return [
                'id' => $a->id,
                'document_id' => $a->document_id,
                'document_number' => $doc?->document_number,
                'client_name' => $doc?->client?->name,
                'invoice_balance' => $doc ? (float) $doc->balance_due : null,
                'user_id' => $a->user_id,
                'user_name' => $a->user?->name,
                'batch_id' => $a->batch_id,
                'commission_type' => $a->commission_type,
                'commission_value' => (float) $a->commission_value,
                'status' => $a->status,
                'paid_out_at' => $a->paid_out_at?->toISOString(),
                'created_at' => $a->created_at?->toISOString(),
            ] + $p;
        })->values();

        return response()->json(['data' => $rows, 'summary' => array_map(fn ($v) => is_float($v) ? round($v, 2) : $v, $totals)]);
    }

    /** Record that the commission of one or more assignments was paid out (outside the system). */
    public function markPaid(Request $request, string $id)
    {
        return $this->doMarkPaid([$id]);
    }

    public function bulkMarkPaid(Request $request)
    {
        $data = $request->validate(['ids' => 'required|array|min:1|max:200', 'ids.*' => 'uuid']);

        return $this->doMarkPaid($data['ids']);
    }

    private function doMarkPaid(array $ids)
    {
        $this->authorizePermission('staff_targets.manage');
        $n = 0;
        foreach (CollectionAssignment::whereIn('id', $ids)->get() as $a) {
            if ($a->paid_out_at || $a->status === 'cancelled') {
                continue;
            }
            $a->update(['paid_out_at' => now(), 'paid_out_by' => auth()->id()]);
            $n++;
        }

        return response()->json(['message' => "$n commission(s) marked as paid.", 'updated' => $n]);
    }

    /**
     * Shared by FollowupController: validate + build assignment attributes for a document.
     * Returns [attrs] or throws a 422 via validation-style JSON error message string.
     */
    public static function buildAttributes(\App\Models\Document $doc, string $userId, ?string $batchId, ?float $targetOverride, ?string $type, ?float $value): array|string
    {
        $balance = (float) $doc->balance_due;
        $target = $targetOverride ?? $balance;
        if ($target <= 0) {
            return 'Collection target must be greater than 0.';
        }
        if ($target > $balance + 0.005) {
            return 'Collection target cannot exceed the invoice balance (' . number_format($balance, 2) . ').';
        }
        $type = $type ?: 'none';
        $value = $type === 'none' ? 0.0 : (float) $value;
        if ($type !== 'none' && $value <= 0) {
            return 'Commission value must be greater than 0.';
        }
        if ($type === 'percentage' && $value > 100) {
            return 'Commission percentage cannot exceed 100.';
        }

        return [
            'document_id' => $doc->id,
            'user_id' => $userId,
            'assigned_by' => auth()->id(),
            'batch_id' => $batchId,
            'target_amount' => round($target, 2),
            'commission_type' => $type,
            'commission_value' => $value,
            'baseline_paid' => (float) $doc->paid_amount,
            'status' => 'active',
        ];
    }
}
