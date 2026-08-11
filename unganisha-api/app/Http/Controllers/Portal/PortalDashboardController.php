<?php

namespace App\Http\Controllers\Portal;

use App\Http\Controllers\Controller;
use App\Models\ClientSubscription;
use App\Models\Document;
use App\Models\PaymentIn;
use App\Models\Refund;
use Carbon\Carbon;
use Illuminate\Http\Request;

class PortalDashboardController extends Controller
{
    public function summary(Request $request)
    {
        $clientUser = $request->user();
        $clientId = $clientUser->client_id;

        $invoices = Document::where('client_id', $clientId)
            ->where('type', 'invoice')
            ->whereNotIn('status', ['draft', 'cancelled']);

        // The three figures below have to describe one set of documents.
        //
        // They previously did not: invoiced summed this client's live invoices
        // while paid summed payments against *any* document of theirs —
        // quotes, proformas, credit notes, and invoices since drafted or
        // cancelled — and ignored refunds entirely. On a client with a long
        // history that drives the balance negative, so the portal reported a
        // large credit to someone holding overdue invoices.
        //
        // Scoped to the same invoices, and netting refunds, this now agrees
        // with Document::getBalanceDueAttribute() summed over those invoices —
        // so the headline matches the rows underneath it.
        $onTheseInvoices = fn ($q) => $q
            ->where('client_id', $clientId)
            ->where('type', 'invoice')
            ->whereNotIn('status', ['draft', 'cancelled']);

        $totalInvoiced = (clone $invoices)->sum('total');
        $totalPaid = round(
            (float) PaymentIn::whereHas('document', $onTheseInvoices)->sum('amount')
            - (float) Refund::whereHas('document', $onTheseInvoices)->sum('amount'),
            2
        );
        $totalBalance = round($totalInvoiced - $totalPaid, 2);

        $overdueCount = (clone $invoices)
            ->where('status', '!=', 'paid')
            ->where('due_date', '<', now())
            ->count();

        // WHMCS-style overview counters
        $servicesCount = ClientSubscription::where('client_id', $clientId)->where('status', 'active')->count();
        $domainsCount  = \App\Models\Domain::where('client_id', $clientId)->whereIn('status', ['active', 'pending'])->count();
        $unpaidCount   = (clone $invoices)->whereIn('status', ['sent', 'overdue', 'partial'])->count();

        // Client-area home widgets
        $client = $clientUser->client;
        $clientInfo = [
            'company' => $client?->name,
            'contact' => $clientUser->name,
            'address' => $client?->address,
            'email'   => $client?->email,
            'phone'   => $client?->phone,
        ];

        $recentServices = ClientSubscription::where('client_id', $clientId)
            ->where('status', '!=', 'cancelled')
            // `meta` carries the cPanel disk figures the dashboard's usage bars
            // need — without it the bars have nothing to render.
            ->with(['productService:id,name', 'hostingAccount:id,client_subscription_id,status,meta'])
            ->orderByRaw("CASE status WHEN 'active' THEN 0 WHEN 'pending' THEN 1 ELSE 2 END")
            ->orderByDesc('start_date')
            ->limit(4)
            ->get()
            ->map(fn ($s) => [
                'id'                 => $s->id,
                'product'            => $s->productService?->name,
                'label'              => $s->label,
                'status'             => $s->status,
                'hosting_account_id' => $s->hostingAccount && $s->hostingAccount->status === 'active'
                                            ? $s->hostingAccount->id : null,
                // Null until the account's usage has been synced from cPanel.
                // The UI must show "not synced", never 0% — an empty bar reads
                // as "plenty of room left".
                'disk_used'          => $s->hostingAccount?->meta['disk_used'] ?? null,
                'disk_limit'         => $s->hostingAccount?->meta['disk_limit'] ?? null,
            ]);

        $expiringDomainsCount = \App\Models\Domain::where('client_id', $clientId)
            ->where('status', 'active')
            ->whereNotNull('expires_at')
            ->whereDate('expires_at', '<=', now()->addDays(45))
            ->count();

        $contacts = \App\Models\ClientUser::where('client_id', $clientId)
            ->where('id', '!=', $clientUser->id)
            ->get(['id', 'name', 'email', 'role'])
            ->map(fn ($u) => ['id' => $u->id, 'name' => $u->name, 'email' => $u->email, 'role' => $u->role]);

        $recentInvoices = Document::where('client_id', $clientId)
            ->where('type', 'invoice')
            ->whereNotIn('status', ['draft', 'cancelled'])
            ->with('items:id,document_id,description')
            ->orderByDesc('date')
            ->limit(5)
            ->get()
            ->map(fn ($doc) => [
                'id' => $doc->id,
                'document_number' => $doc->document_number,
                'description' => $doc->items->first()?->description ?? $doc->notes,
                'date' => $doc->date->format('Y-m-d'),
                'due_date' => $doc->due_date?->format('Y-m-d'),
                'total' => (float) $doc->total,
                'paid' => (float) $doc->paid_amount,
                'balance' => (float) $doc->balance_due,
                'status' => $doc->status,
            ]);

        $recentPayments = PaymentIn::whereHas('document', fn ($q) => $q->where('client_id', $clientId))
            ->with('document:id,document_number')
            ->orderByDesc('payment_date')
            ->limit(5)
            ->get()
            ->map(fn ($p) => [
                'id' => $p->id,
                'payment_date' => $p->payment_date,
                'amount' => (float) $p->amount,
                'payment_method' => $p->payment_method,
                'reference' => $p->reference,
                'document_number' => $p->document?->document_number,
            ]);

        // Upcoming subscription schedule
        $cycleIntervals = [
            'monthly' => '1 month',
            'quarterly' => '3 months',
            'half_yearly' => '6 months',
            'yearly' => '1 year',
        ];
        $cycleLabels = [
            'once' => 'One-time',
            'monthly' => 'Monthly',
            'quarterly' => 'Quarterly',
            'half_yearly' => 'Half Yearly',
            'yearly' => 'Yearly',
        ];

        $subscriptions = ClientSubscription::where('client_id', $clientId)
            ->where('status', 'active')
            ->with('productService:id,name,price,billing_cycle')
            ->get()
            ->map(function ($sub) use ($cycleIntervals, $cycleLabels) {
                $cycle = $sub->productService?->billing_cycle;
                $nextDate = null;

                if ($cycle && $cycle !== 'once' && isset($cycleIntervals[$cycle])) {
                    $interval = $cycleIntervals[$cycle];

                    // Use expire_date if available, otherwise fall back to start_date
                    if ($sub->expire_date) {
                        $next = Carbon::parse($sub->expire_date);
                        while ($next->lt(Carbon::today())) {
                            $next->add($interval);
                        }
                    } else {
                        $next = Carbon::parse($sub->start_date);
                        while ($next->lte(Carbon::today())) {
                            $next->add($interval);
                        }
                    }

                    $nextDate = $next->format('Y-m-d');
                }

                return [
                    'id' => $sub->id,
                    'service' => $sub->productService?->name,
                    'label' => $sub->label,
                    'price' => (float) ($sub->productService?->price ?? 0),
                    'quantity' => $sub->quantity,
                    'schedule' => $cycleLabels[$cycle] ?? $cycle,
                    'next_invoice_date' => $nextDate,
                ];
            })
            ->sortBy('next_invoice_date')
            ->values();

        return response()->json([
            'credit_balance' => (float) ($client?->credit_balance ?? 0),
            'services_count' => $servicesCount,
            'domains_count' => $domainsCount,
            'tickets_count' => \App\Models\Ticket::where('client_id', $clientId)->where('status', '!=', 'closed')->count(),
            'unpaid_invoices_count' => $unpaidCount,
            'client_info' => $clientInfo,
            'recent_services' => $recentServices,
            'expiring_domains_count' => $expiringDomainsCount,
            'contacts' => $contacts,
            'recent_tickets' => \App\Models\Ticket::where('client_id', $clientId)
                ->orderByDesc('last_reply_at')->limit(5)
                ->get(['id', 'ticket_number', 'subject', 'status', 'last_reply_at'])
                ->map(fn ($t) => [
                    'id' => $t->id, 'ticket_number' => $t->ticket_number, 'subject' => $t->subject,
                    'status' => $t->status, 'last_reply_at' => $t->last_reply_at?->toISOString(),
                ]),
            'announcements' => \App\Models\Announcement::withoutGlobalScopes()
                ->where('tenant_id', $clientUser->tenant_id)->published()
                ->orderByDesc('published_at')->limit(3)
                ->get(['id', 'title', 'body', 'published_at'])
                ->map(fn ($a) => [
                    'id' => $a->id, 'title' => $a->title,
                    'excerpt' => \Illuminate\Support\Str::limit(strip_tags($a->body), 140),
                    'published_at' => $a->published_at->toISOString(),
                ]),
            'total_invoiced' => $totalInvoiced,
            'total_paid' => $totalPaid,
            'total_balance' => $totalBalance,
            'overdue_count' => $overdueCount,
            'recent_invoices' => $recentInvoices,
            'recent_payments' => $recentPayments,
            'upcoming_subscriptions' => $subscriptions,
        ]);
    }
}
