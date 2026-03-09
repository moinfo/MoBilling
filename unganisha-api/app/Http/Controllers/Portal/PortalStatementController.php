<?php

namespace App\Http\Controllers\Portal;

use App\Http\Controllers\Controller;
use App\Models\Document;
use App\Models\PaymentIn;
use Illuminate\Http\Request;

class PortalStatementController extends Controller
{
    public function index(Request $request)
    {
        $clientId = $request->user()->client_id;
        $startDate = $request->get('start_date');
        $endDate = $request->get('end_date');

        // Get invoices
        $invoiceQuery = Document::where('client_id', $clientId)
            ->where('type', 'invoice')
            ->whereNotIn('status', ['draft', 'cancelled'])
            ->orderBy('date');

        if ($startDate) $invoiceQuery->where('date', '>=', $startDate);
        if ($endDate) $invoiceQuery->where('date', '<=', $endDate);

        $invoices = $invoiceQuery->get();

        // Get payments
        $paymentQuery = PaymentIn::whereHas('document', fn ($q) => $q->where('client_id', $clientId))
            ->with('document:id,document_number')
            ->orderBy('payment_date');

        if ($startDate) $paymentQuery->where('payment_date', '>=', $startDate);
        if ($endDate) $paymentQuery->where('payment_date', '<=', $endDate);

        $payments = $paymentQuery->get();

        // Build statement entries
        $entries = [];

        foreach ($invoices as $inv) {
            $entries[] = [
                'date' => $inv->date->format('Y-m-d'),
                'type' => 'invoice',
                'reference' => $inv->document_number,
                'description' => "Invoice {$inv->document_number}",
                'debit' => (float) $inv->total,
                'credit' => 0,
            ];
        }

        foreach ($payments as $p) {
            $entries[] = [
                'date' => $p->payment_date,
                'type' => 'payment',
                'reference' => $p->reference ?? $p->document?->document_number,
                'description' => "Payment - {$p->payment_method}",
                'debit' => 0,
                'credit' => (float) $p->amount,
            ];
        }

        // Sort by date
        usort($entries, fn ($a, $b) => $a['date'] <=> $b['date']);

        // Add running balance
        $balance = 0;
        foreach ($entries as &$entry) {
            $balance += $entry['debit'] - $entry['credit'];
            $entry['balance'] = $balance;
        }

        $totalDebits = array_sum(array_column($entries, 'debit'));
        $totalCredits = array_sum(array_column($entries, 'credit'));

        return response()->json([
            'entries' => $entries,
            'total_debits' => $totalDebits,
            'total_credits' => $totalCredits,
            'closing_balance' => $balance,
        ]);
    }
}
