<?php

namespace App\Http\Controllers;

use App\Models\RegistrarAccount;
use App\Models\RegistrarCreditTransfer;
use App\Services\Registrar\FredHttpDriver;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;

/**
 * Zone credit transfer REQUESTS. TZNIC has no API to move credit between zones,
 * so this records the intent (pending) + generates a ready-to-send email to the
 * registry, and lets staff mark it completed once the registry has actioned it.
 * The live balance card is never altered by a pending request.
 */
class RegistrarCreditTransferController extends Controller
{
    public function index()
    {
        $transfers = RegistrarCreditTransfer::orderByRaw("status = 'pending' desc")
            ->orderByDesc('created_at')->limit(50)->get()
            ->map(fn ($tf) => [
                'id'          => $tf->id,
                'from_zone'   => $tf->from_zone,
                'to_zone'     => $tf->to_zone,
                'amount'      => (float) $tf->amount,
                'status'      => $tf->status,
                'reference'   => $tf->reference,
                'notes'       => $tf->notes,
                'requested_by'=> $tf->requested_by_name,
                'created_at'  => $tf->created_at->toISOString(),
                'completed_at'=> $tf->completed_at?->toISOString(),
            ]);

        return response()->json(['data' => $transfers]);
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'from_zone' => 'required|string|max:30',
            'to_zone'   => 'required|string|max:30|different:from_zone',
            'amount'    => 'required|numeric|min:1',
            'notes'     => 'nullable|string|max:1000',
        ]);

        $account = RegistrarAccount::whereNull('tenant_id')->where('is_active', true)->first();
        abort_unless($account, 422, 'No active platform registrar account.');

        // Guard against requesting more than the from-zone actually holds (live).
        $credits = collect(Cache::get('registrar_credit')['zones'] ?? []);
        if ($credits->isEmpty()) {
            try {
                $credits = collect((new FredHttpDriver($account))->credit())
                    ->map(fn ($c) => ['zone' => $c['zone'], 'credit' => (float) $c['credit']]);
            } catch (\Throwable) {
                $credits = collect();
            }
        }
        $fromBalance = (float) ($credits->firstWhere('zone', $data['from_zone'])['credit'] ?? 0);
        if ($fromBalance > 0 && $data['amount'] > $fromBalance) {
            return response()->json([
                'message' => "Amount exceeds the .{$data['from_zone']} balance (" . number_format($fromBalance, 2) . ').',
            ], 422);
        }

        $user = auth()->user();
        $transfer = RegistrarCreditTransfer::create([
            'registrar_account_id' => $account->id,
            'from_zone'            => strtolower($data['from_zone']),
            'to_zone'              => strtolower($data['to_zone']),
            'amount'               => round((float) $data['amount'], 2),
            'status'               => 'pending',
            'notes'                => $data['notes'] ?? null,
            'requested_by'         => $user?->id,
            'requested_by_name'    => $user?->name,
        ]);

        return response()->json([
            'data'  => [
                'id'        => $transfer->id,
                'from_zone' => $transfer->from_zone,
                'to_zone'   => $transfer->to_zone,
                'amount'    => (float) $transfer->amount,
                'status'    => $transfer->status,
            ],
            // ready-to-send email for the registry — staff copies or opens in mail client
            'email' => $this->registryEmail($account, $transfer),
            'message' => 'Transfer request logged (pending). Send the generated email to TZNIC to action it — the balance updates after they process it.',
        ], 201);
    }

    public function complete(Request $request, RegistrarCreditTransfer $registrarCreditTransfer)
    {
        abort_unless($registrarCreditTransfer->status === 'pending', 422, 'Only pending requests can be completed.');

        $data = $request->validate(['reference' => 'nullable|string|max:255']);

        $registrarCreditTransfer->update([
            'status'       => 'completed',
            'reference'    => $data['reference'] ?? null,
            'completed_at' => now(),
        ]);

        // Force a fresh balance read on next load so the confirmed move shows.
        Cache::forget('registrar_credit');

        return response()->json(['message' => 'Marked completed — refresh the balance to confirm.']);
    }

    public function cancel(RegistrarCreditTransfer $registrarCreditTransfer)
    {
        abort_unless($registrarCreditTransfer->status === 'pending', 422, 'Only pending requests can be cancelled.');
        $registrarCreditTransfer->update(['status' => 'cancelled']);

        return response()->json(['message' => 'Transfer request cancelled.']);
    }

    private function registryEmail(RegistrarAccount $account, RegistrarCreditTransfer $tf): array
    {
        $reg = $account->registrar_id ?: 'our registrar account';
        $amount = number_format((float) $tf->amount, 2);

        $subject = "Credit reallocation request — {$reg}: .{$tf->from_zone} → .{$tf->to_zone}";
        $body = "Dear TZNIC,\n\n"
            . "Please reallocate registrar credit for our account {$reg} as follows:\n\n"
            . "  From zone:  .{$tf->from_zone}\n"
            . "  To zone:    .{$tf->to_zone}\n"
            . "  Amount:     {$amount} TZS\n\n"
            . "Kindly confirm once processed.\n\nThank you,\n" . ($tf->requested_by_name ?: 'Registrar admin');

        return [
            'to'      => config('registrar.registry_email', 'info@tznic.or.tz'),
            'subject' => $subject,
            'body'    => $body,
        ];
    }
}
