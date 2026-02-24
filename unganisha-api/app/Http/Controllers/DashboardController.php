<?php

namespace App\Http\Controllers;

use App\Models\Bill;
use App\Models\Document;
use App\Models\PaymentIn;
use App\Services\ResellerService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class DashboardController extends Controller
{
    public function summary(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        // Invoice stats
        $invoices = Document::where('type', 'invoice');
        $totalReceivable = (clone $invoices)->sum('total');
        $totalReceived = PaymentIn::sum('amount');
        $overdueInvoices = (clone $invoices)
            ->where('status', '!=', 'paid')
            ->whereNotNull('due_date')
            ->where('due_date', '<', now())
            ->count();

        // Recent invoices
        $recentInvoices = Document::with('client')
            ->where('type', 'invoice')
            ->orderByDesc('created_at')
            ->limit(5)
            ->get()
            ->map(fn ($doc) => [
                'id' => $doc->id,
                'document_number' => $doc->document_number,
                'client_name' => $doc->client?->name,
                'total' => $doc->total,
                'status' => $doc->status,
                'date' => $doc->date?->format('Y-m-d'),
            ]);

        // Upcoming bills
        $upcomingBills = Bill::where('is_active', true)
            ->where('due_date', '>=', now()->toDateString())
            ->orderBy('due_date')
            ->limit(5)
            ->get()
            ->map(fn ($bill) => [
                'id' => $bill->id,
                'name' => $bill->name,
                'amount' => $bill->amount,
                'due_date' => $bill->due_date?->format('Y-m-d'),
                'category' => $bill->category,
            ]);

        // Overdue bills
        $overdueBills = Bill::where('is_active', true)
            ->where('due_date', '<', now()->toDateString())
            ->count();

        // Counts
        $totalClients = \App\Models\Client::count();
        $totalDocuments = Document::count();

        // SMS balance
        $smsBalance = null;
        $tenant = auth()->user()->tenant;
        if ($tenant && $tenant->sms_enabled && $tenant->sms_authorization) {
            try {
                $reseller = new ResellerService();
                $balanceResult = $reseller->getBalance($tenant);
                $smsBalance = $balanceResult['data']['sms_balance'] ?? $balanceResult['sms_balance'] ?? null;
            } catch (\Throwable $e) {
                Log::warning('Dashboard: failed to fetch SMS balance', ['error' => $e->getMessage()]);
            }
        }

        return response()->json([
            'total_receivable' => round($totalReceivable, 2),
            'total_received' => round($totalReceived, 2),
            'outstanding' => round($totalReceivable - $totalReceived, 2),
            'overdue_invoices' => $overdueInvoices,
            'overdue_bills' => $overdueBills,
            'total_clients' => $totalClients,
            'total_documents' => $totalDocuments,
            'sms_balance' => $smsBalance,
            'sms_enabled' => $tenant?->sms_enabled ?? false,
            'recent_invoices' => $recentInvoices,
            'upcoming_bills' => $upcomingBills,
        ]);
    }
}
