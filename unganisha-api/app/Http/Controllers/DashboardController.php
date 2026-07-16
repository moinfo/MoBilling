<?php

namespace App\Http\Controllers;

use App\Models\Bill;
use App\Models\Client;
use App\Models\ClientSubscription;
use App\Models\Document;
use App\Models\Domain;
use App\Models\Expense;
use App\Models\Followup;
use App\Models\HostingAccount;
use App\Models\Ticket;
use App\Models\PaymentIn;
use App\Models\SatisfactionCall;
use App\Models\Statutory;
use App\Services\ResellerService;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

class DashboardController extends Controller
{
    public function summary(Request $request)
    {
        $user = auth()->user();
        $tenantId = $user->tenant_id;
        // Each dashboard metric is gated by its own dashboard.* permission —
        // withheld data is neither computed nor returned (not just hidden in UI).
        $can = fn (string $p) => $user->hasPermission($p);

        $month = (int) $request->query('month', now()->month);
        $year  = (int) $request->query('year', now()->year);
        $periodStart = Carbon::createFromDate($year, $month, 1)->startOfMonth();
        $periodEnd   = $periodStart->copy()->endOfMonth();

        // Invoice money stats (only if any of the three money cards is allowed)
        $totalReceivable = 0.0;
        $totalReceived = 0.0;
        if ($can('dashboard.total_receivable') || $can('dashboard.total_received') || $can('dashboard.outstanding')) {
            $totalReceivable = (float) Document::where('type', 'invoice')
                ->whereBetween('date', [$periodStart->toDateString(), $periodEnd->toDateString()])->sum('total');
            $totalReceived = (float) PaymentIn::whereBetween('payment_date', [$periodStart->toDateString(), $periodEnd->toDateString()])->sum('amount');
        }
        $overdueInvoices = $can('dashboard.overdue_invoices')
            ? Document::where('type', 'invoice')->where('status', '!=', 'paid')
                ->whereNotNull('due_date')->where('due_date', '<', now())->count()
            : null;

        // Recent invoices
        $recentInvoices = $can('dashboard.recent_invoices')
            ? Document::with(['client', 'items:id,document_id,description'])
                ->where('type', 'invoice')->orderByDesc('created_at')->limit(5)->get()
                ->map(fn ($doc) => [
                    'id' => $doc->id,
                    'document_number' => $doc->document_number,
                    'description' => $doc->items->first()?->description ?? $doc->notes,
                    'client_name' => $doc->client?->name,
                    'total' => $doc->total,
                    'status' => $doc->status,
                    'date' => $doc->date?->format('Y-m-d'),
                ])
            : [];

        // Upcoming bills
        $upcomingBills = $can('dashboard.upcoming_bills')
            ? Bill::where('is_active', true)->where('due_date', '>=', now()->toDateString())
                ->orderBy('due_date')->limit(5)->get()
                ->map(fn ($bill) => [
                    'id' => $bill->id,
                    'name' => $bill->name,
                    'amount' => $bill->amount,
                    'due_date' => $bill->due_date?->format('Y-m-d'),
                    'category' => $bill->category,
                ])
            : [];

        // Overdue bills
        $overdueBills = $can('dashboard.overdue_bills')
            ? Bill::where('is_active', true)->where('due_date', '<', now()->toDateString())->count()
            : null;

        // Counts
        $totalClients = $can('dashboard.total_clients') ? Client::count() : null;
        $totalDocuments = $can('dashboard.total_documents') ? Document::count() : null;

        // SMS balance (skip the live reseller call entirely if not permitted)
        $smsBalance = null;
        $tenant = $user->tenant;
        if ($can('dashboard.sms_balance') && $tenant && $tenant->sms_enabled && $tenant->sms_authorization) {
            try {
                $reseller = new ResellerService();
                $balanceResult = $reseller->getBalance($tenant);
                $smsBalance = $balanceResult['data']['sms_balance'] ?? $balanceResult['sms_balance'] ?? null;
            } catch (\Throwable $e) {
                Log::warning('Dashboard: failed to fetch SMS balance', ['error' => $e->getMessage()]);
            }
        }

        // --- Chart data ---

        // Monthly revenue (last 6 months): invoiced vs collected
        $monthlyRevenue = collect();
        if ($can('dashboard.revenue_chart')) {
            $sixMonthsAgo = Carbon::now()->subMonths(5)->startOfMonth();
            $monthlyInvoiced = Document::where('type', 'invoice')
                ->where('date', '>=', $sixMonthsAgo)
                ->selectRaw("DATE_FORMAT(date, '%Y-%m') as month, SUM(total) as invoiced")
                ->groupBy('month')
                ->pluck('invoiced', 'month');

            $monthlyCollected = PaymentIn::where('payment_date', '>=', $sixMonthsAgo)
                ->selectRaw("DATE_FORMAT(payment_date, '%Y-%m') as month, SUM(amount) as collected")
                ->groupBy('month')
                ->pluck('collected', 'month');

            for ($i = 5; $i >= 0; $i--) {
                $date = Carbon::now()->subMonths($i);
                $key = $date->format('Y-m');
                $monthlyRevenue->push([
                    'month' => $date->format('M'),
                    'invoiced' => round((float) ($monthlyInvoiced[$key] ?? 0), 2),
                    'collected' => round((float) ($monthlyCollected[$key] ?? 0), 2),
                ]);
            }
        }

        // Invoice status breakdown for selected month
        $invoiceStatusBreakdown = $can('dashboard.invoice_status_chart')
            ? Document::where('type', 'invoice')
                ->whereBetween('date', [$periodStart->toDateString(), $periodEnd->toDateString()])
                ->selectRaw('status, COUNT(*) as count')->groupBy('status')->get()
                ->map(fn ($row) => ['status' => $row->status, 'count' => (int) $row->count])
            : [];

        // Payment method breakdown for selected month
        $paymentMethodBreakdown = $can('dashboard.payment_method_chart')
            ? PaymentIn::whereBetween('payment_date', [$periodStart->toDateString(), $periodEnd->toDateString()])
                ->selectRaw('payment_method, SUM(amount) as amount')->groupBy('payment_method')->get()
                ->map(fn ($row) => ['method' => $row->payment_method, 'amount' => round((float) $row->amount, 2)])
            : [];

        // Top 5 clients by invoiced amount
        $topClients = $can('dashboard.top_clients')
            ? Document::with('client')->where('type', 'invoice')
                ->selectRaw('client_id, SUM(total) as total')->groupBy('client_id')
                ->orderByDesc('total')->limit(5)->get()
                ->map(function ($row) {
                    $paid = PaymentIn::whereHas('document', fn ($q) => $q->where('client_id', $row->client_id))->sum('amount');
                    return [
                        'name' => $row->client?->name ?? 'Unknown',
                        'total' => round((float) $row->total, 2),
                        'paid' => round((float) $paid, 2),
                    ];
                })
            : [];

        // Subscription stats
        $subscriptionStats = null;
        if ($can('dashboard.subscription_stats')) {
            $subscriptionCounts = ClientSubscription::selectRaw('status, COUNT(*) as count')
                ->groupBy('status')->pluck('count', 'status');
            $subscriptionStats = [
                'active' => (int) ($subscriptionCounts['active'] ?? 0),
                'pending' => (int) ($subscriptionCounts['pending'] ?? 0),
                'cancelled' => (int) ($subscriptionCounts['cancelled'] ?? 0),
            ];
        }

        // Upcoming renewals (next 5 subscriptions due based on start_date + billing_cycle)
        $upcomingRenewals = !$can('dashboard.upcoming_renewals') ? collect() : ClientSubscription::with(['client', 'productService'])
            ->where('status', 'active')
            ->get()
            ->map(function ($sub) {
                $cycle = $sub->productService?->billing_cycle;
                $startDate = $sub->start_date;
                if (!$startDate || !$cycle) {
                    return null;
                }

                $nextBill = Carbon::parse($startDate);
                $now = Carbon::now();

                // Advance next_bill_date until it's in the future
                while ($nextBill->lte($now)) {
                    $nextBill = match ($cycle) {
                        'weekly' => $nextBill->addWeek(),
                        'monthly' => $nextBill->addMonth(),
                        'quarterly' => $nextBill->addMonths(3),
                        'semi_annual' => $nextBill->addMonths(6),
                        'annual', 'yearly' => $nextBill->addYear(),
                        default => $nextBill->addMonth(),
                    };
                }

                // Skip forward past dates that already have a paid invoice
                $cycleIntervals = [
                    'weekly' => '1 week', 'monthly' => '1 month', 'quarterly' => '3 months',
                    'semi_annual' => '6 months', 'annual' => '1 year', 'yearly' => '1 year',
                ];
                $interval = $cycleIntervals[$cycle] ?? '1 month';
                while (
                    \App\Models\RecurringInvoiceLog::where('client_id', $sub->client_id)
                        ->where('product_service_id', $sub->product_service_id)
                        ->where('next_bill_date', $nextBill->format('Y-m-d'))
                        ->whereHas('document', fn ($q) => $q->where('status', 'paid'))
                        ->exists()
                ) {
                    $nextBill->add($interval);
                }

                return [
                    'client_name' => $sub->client?->name ?? 'Unknown',
                    'product_name' => $sub->productService?->name ?? 'Unknown',
                    'label' => $sub->label,
                    'next_bill_date' => $nextBill->format('Y-m-d'),
                    'price' => round((float) ($sub->productService?->price ?? 0), 2),
                ];
            })
            ->filter()
            ->sortBy('next_bill_date')
            ->take(5)
            ->values();

        // Statutory obligations — shared by the two obligation cards, the
        // urgent-obligations list, and the calendar; fetched once if any needs it.
        $canObligationStats = $can('dashboard.overdue_obligations') || $can('dashboard.due_soon_obligations');
        $needStatutory = $canObligationStats || $can('dashboard.urgent_obligations') || $can('dashboard.activity_calendar');
        $activeStatutories = $needStatutory ? Statutory::where('is_active', true)->get() : collect();
        $today = now()->toDateString();

        $statutoryStats = null;
        if ($canObligationStats) {
            $statutoryStats = [
                'total_active' => $activeStatutories->count(),
                'overdue' => $activeStatutories->filter(fn ($s) => $s->next_due_date->lt($today))->count(),
                'due_soon' => $activeStatutories->filter(
                    fn ($s) => !$s->next_due_date->lt($today) && $s->next_due_date->diffInDays(now(), false) >= -$s->remind_days_before
                )->count(),
            ];
        }

        // Overdue / due-soon obligations for dashboard list
        $urgentObligations = !$can('dashboard.urgent_obligations') ? collect() : $activeStatutories
            ->filter(fn ($s) => $s->next_due_date->lte(now()->addDays($s->remind_days_before)))
            ->sortBy('next_due_date')
            ->take(5)
            ->map(fn ($s) => [
                'id' => $s->id,
                'name' => $s->name,
                'amount' => $s->amount,
                'next_due_date' => $s->next_due_date->format('Y-m-d'),
                'days_remaining' => (int) now()->startOfDay()->diffInDays($s->next_due_date, false),
                'cycle' => $s->cycle,
            ])
            ->values();

        // Total expenses for selected month
        $totalExpenses = $can('dashboard.expenses')
            ? (float) Expense::whereBetween('expense_date', [$periodStart->toDateString(), $periodEnd->toDateString()])->sum('amount')
            : null;

        // Daily activities for the calendar (current month ± 1 month)
        $calStart = now()->subMonth()->startOfMonth()->toDateString();
        $calEnd = now()->addMonth()->endOfMonth()->toDateString();

        $calendarData = [];
        if ($can('dashboard.activity_calendar')) {
        $calendarItems = collect();

        // Followups with client info
        Followup::with('client')
            ->whereIn('status', ['pending', 'open'])
            ->whereNotNull('next_followup')
            ->whereDate('next_followup', '>=', $calStart)
            ->whereDate('next_followup', '<=', $calEnd)
            ->whereHas('document', fn ($q) => $q->where('status', '!=', 'cancelled'))
            ->get()
            ->each(function ($f) use ($calendarItems) {
                $calendarItems->push([
                    'date' => $f->next_followup->format('Y-m-d'),
                    'type' => 'followup',
                    'label' => $f->client?->name ?? 'Unknown',
                    'detail' => $f->document?->document_number,
                ]);
            });

        // Satisfaction calls
        SatisfactionCall::with('client')
            ->where('status', 'scheduled')
            ->whereDate('scheduled_date', '>=', $calStart)
            ->whereDate('scheduled_date', '<=', $calEnd)
            ->get()
            ->each(function ($c) use ($calendarItems) {
                $calendarItems->push([
                    'date' => $c->scheduled_date->format('Y-m-d'),
                    'type' => 'satisfaction',
                    'label' => $c->client?->name ?? 'Unknown',
                    'detail' => null,
                ]);
            });

        // Appointments
        SatisfactionCall::with('client')
            ->where('appointment_requested', true)
            ->whereIn('appointment_status', ['pending', 'confirmed'])
            ->whereDate('appointment_date', '>=', $calStart)
            ->whereDate('appointment_date', '<=', $calEnd)
            ->get()
            ->each(function ($c) use ($calendarItems) {
                $calendarItems->push([
                    'date' => $c->appointment_date->format('Y-m-d'),
                    'type' => 'appointment',
                    'label' => $c->client?->name ?? 'Unknown',
                    'detail' => $c->appointment_notes,
                ]);
            });

        // Invoice due dates
        Document::with('client')
            ->where('type', 'invoice')
            ->whereNotIn('status', ['paid', 'draft', 'cancelled'])
            ->whereDate('due_date', '>=', $calStart)
            ->whereDate('due_date', '<=', $calEnd)
            ->get()
            ->each(function ($d) use ($calendarItems) {
                $calendarItems->push([
                    'date' => $d->due_date->format('Y-m-d'),
                    'type' => 'invoice',
                    'label' => $d->client?->name ?? 'Unknown',
                    'detail' => $d->document_number . ' — ' . number_format($d->balance_due, 0),
                ]);
            });

        // Bill due dates
        Bill::whereNull('paid_at')
            ->where('is_active', true)
            ->whereDate('due_date', '>=', $calStart)
            ->whereDate('due_date', '<=', $calEnd)
            ->get()
            ->each(function ($b) use ($calendarItems) {
                $calendarItems->push([
                    'date' => $b->due_date->format('Y-m-d'),
                    'type' => 'bill',
                    'label' => $b->name,
                    'detail' => number_format($b->amount, 0),
                ]);
            });

        // Statutory due dates
        $activeStatutories
            ->filter(fn ($s) => $s->next_due_date->gte($calStart) && $s->next_due_date->lte($calEnd))
            ->each(function ($s) use ($calendarItems) {
                $calendarItems->push([
                    'date' => $s->next_due_date->format('Y-m-d'),
                    'type' => 'statutory',
                    'label' => $s->name,
                    'detail' => number_format($s->amount, 0),
                ]);
            });

        // Field visit follow-ups where the officer is the current user
        \App\Models\FieldVisit::where('officer_id', auth()->id())
            ->whereNotNull('next_followup_date')
            ->whereDate('next_followup_date', '>=', $calStart)
            ->whereDate('next_followup_date', '<=', $calEnd)
            ->get()
            ->each(function ($v) use ($calendarItems) {
                $calendarItems->push([
                    'date'   => $v->next_followup_date->format('Y-m-d'),
                    'type'   => 'field_followup',
                    'label'  => $v->business_name,
                    'detail' => $v->location,
                ]);
            });

        // WhatsApp follow-ups assigned to the current user
        \App\Models\WhatsappContact::where('assigned_to', auth()->id())
            ->whereNotNull('next_followup_date')
            ->whereDate('next_followup_date', '>=', $calStart)
            ->whereDate('next_followup_date', '<=', $calEnd)
            ->get()
            ->each(function ($wa) use ($calendarItems) {
                $calendarItems->push([
                    'date'   => $wa->next_followup_date->format('Y-m-d'),
                    'type'   => 'whatsapp',
                    'label'  => $wa->name,
                    'detail' => $wa->phone,
                ]);
            });

        // Group by date
        $calendarData = $calendarItems->groupBy('date')->map(fn ($items, $date) => [
            'date' => $date,
            'items' => $items->map(fn ($i) => [
                'type' => $i['type'],
                'label' => $i['label'],
                'detail' => $i['detail'],
            ])->values(),
        ])->values();
        } // end activity_calendar gate

        $totalWhatsappContacts = $can('dashboard.whatsapp_contacts') ? \App\Models\WhatsappContact::count() : null;
        $totalFieldVisits      = $can('dashboard.field_visits') ? \App\Models\FieldVisit::count() : null;

        // System Records — the systems breakdown and the bank breakdown are two
        // separate cards; compute the shared base only if at least one is allowed,
        // and include each list only for its own permission.
        $systemRecords = null;
        $canSystemsCard = $can('dashboard.system_records_breakdown');
        $canBankCard = $can('dashboard.bank_account_breakdown');
        if ($canSystemsCard || $canBankCard) {
            $systemRecordRows = DB::table('system_records as sr')
                ->join('systems as s', 's.id', '=', 'sr.system_id')
                ->join('system_properties as sp', 'sp.id', '=', 'sr.system_property_id')
                ->where('sr.tenant_id', $tenantId)
                ->whereNull('sr.deleted_at')
                ->whereBetween('sr.record_date', [$periodStart->toDateString(), $periodEnd->toDateString()])
                ->selectRaw('s.name as system_name, sp.name as system_property_name, SUM(sr.amount) as total')
                ->groupBy('s.name', 'sp.name')
                ->orderBy('s.name')
                ->orderBy('sp.name')
                ->get();

            $systemRecordsBreakdown = $canSystemsCard
                ? collect($systemRecordRows)
                    ->groupBy('system_name')
                    ->map(fn ($props, $name) => [
                        'name' => $name,
                        'subtotal' => round((float) $props->sum('total'), 2),
                        'properties' => $props->map(fn ($p) => [
                            'name' => $p->system_property_name,
                            'total' => round((float) $p->total, 2),
                        ])->values(),
                    ])
                    ->values()
                : [];

            $byBank = [];
            if ($canBankCard) {
                $bankRows = DB::table('system_records as sr')
                    ->leftJoin('bank_accounts as ba', 'ba.id', '=', 'sr.bank_account_id')
                    ->where('sr.tenant_id', $tenantId)
                    ->whereNull('sr.deleted_at')
                    ->whereBetween('sr.record_date', [$periodStart->toDateString(), $periodEnd->toDateString()])
                    ->selectRaw('sr.bank_account_id, MAX(ba.bank_name) as bank_name, MAX(ba.account_number) as account_number, SUM(sr.amount) as total')
                    ->groupBy('sr.bank_account_id')
                    ->orderByRaw('CASE WHEN sr.bank_account_id IS NULL THEN 1 ELSE 0 END')
                    ->orderBy('bank_name')
                    ->get();

                $byBank = collect($bankRows)->map(fn ($r) => [
                    'bank_account_id' => $r->bank_account_id,
                    'bank_name' => $r->bank_name ?? 'Untagged / Cash',
                    'account_number' => $r->account_number,
                    'total' => round((float) $r->total, 2),
                ])->values();
            }

            $systemRecords = [
                'total' => round((float) collect($systemRecordRows)->sum('total'), 2),
                'systems' => $systemRecordsBreakdown,
                'by_bank' => $byBank,
            ];
        }

        // ── Hosting & Domains (permission-gated; only compute what's shown) ──
        $canHosting = $can('dashboard.hosting');
        $canDomains = $can('dashboard.domains');
        $canTickets = $can('dashboard.tickets');

        $hostingDomains = null;
        if ($canHosting || $canDomains) {
            $hostingDomains = ['can' => ['hosting' => $canHosting, 'domains' => $canDomains, 'tickets' => $canTickets]];

            if ($canHosting) {
                $hostingCounts = HostingAccount::selectRaw('status, COUNT(*) as c')->groupBy('status')->pluck('c', 'status');
                $hostingDomains['hosting'] = [
                    'total'     => (int) $hostingCounts->sum(),
                    'active'    => (int) ($hostingCounts['active'] ?? 0),
                    'suspended' => (int) ($hostingCounts['suspended'] ?? 0),
                ];
            }

            if ($canDomains) {
                $domainCounts = Domain::selectRaw('status, COUNT(*) as c')->groupBy('status')->pluck('c', 'status');
                $domainsExpiringSoon = Domain::where('status', 'active')
                    ->whereNotNull('expires_at')
                    ->whereBetween('expires_at', [now()->toDateString(), now()->copy()->addDays(45)->toDateString()])
                    ->count();

                $hostingDomains['domains'] = [
                    'total'         => (int) $domainCounts->sum(),
                    'active'        => (int) ($domainCounts['active'] ?? 0),
                    'expiring_soon' => $domainsExpiringSoon,
                ];

                $hostingDomains['expiring_domains'] = Domain::with('client:id,name')
                    ->where('status', 'active')
                    ->whereNotNull('expires_at')
                    ->where('expires_at', '<=', now()->copy()->addDays(60)->toDateString())
                    ->orderBy('expires_at')
                    ->limit(6)
                    ->get()
                    ->map(fn ($d) => [
                        'id'          => $d->id,
                        'name'        => $d->name,
                        'client_name' => $d->client?->name,
                        'expires_at'  => $d->expires_at?->format('Y-m-d'),
                        'days_left'   => (int) now()->startOfDay()->diffInDays($d->expires_at, false),
                        'auto_renew'  => (bool) $d->auto_renew,
                    ]);

                // Registrar prepaid credit — served from the shared cache; on a
                // cold cache do ONE live read so the card isn't blank, and cache
                // only on success (a registry hiccup must not stick for 15 min).
                $creditCache = \Illuminate\Support\Facades\Cache::get('registrar_credit');
                if ($creditCache === null) {
                    try {
                        $acct = \App\Models\RegistrarAccount::whereNull('tenant_id')->where('is_active', true)->first();
                        if ($acct) {
                            $zones = collect((new \App\Services\Registrar\FredHttpDriver($acct))->credit())
                                ->map(fn ($c) => ['zone' => $c['zone'], 'credit' => (float) $c['credit']])->all();
                            $creditCache = ['ok' => true, 'zones' => $zones, 'checked_at' => now()->toISOString()];
                            \Illuminate\Support\Facades\Cache::put('registrar_credit', $creditCache, now()->addMinutes(15));
                        }
                    } catch (\Throwable $e) {
                        Log::warning('Dashboard: registrar credit fetch failed', ['error' => $e->getMessage()]);
                    }
                }
                $registrarCredit = collect($creditCache['zones'] ?? [])->filter(fn ($z) => ($z['credit'] ?? 0) > 0);
                $hostingDomains['registrar_credit_total'] = $registrarCredit->isEmpty() ? null : round((float) $registrarCredit->sum('credit'), 2);
            }

            if ($canTickets) {
                $hostingDomains['open_tickets'] = Ticket::whereIn('status', ['open', 'customer_reply'])->count();
            }
        }

        // ── My report deductions (personal — shown to report submitters) ──
        $staffPenalties = null;
        if ($can('staff_reports.submit')) {
            $monthStart = now()->startOfMonth()->toDateString();
            $monthEnd   = now()->endOfMonth()->toDateString();

            $rows = \App\Models\StaffReportPenalty::withoutGlobalScopes()
                ->where('user_id', $user->id)
                ->where('waived', false)
                ->orderByDesc('period_date')->orderByDesc('created_at')
                ->limit(15)->get();

            $monthTotal = \App\Models\StaffReportPenalty::withoutGlobalScopes()
                ->where('user_id', $user->id)->where('waived', false)
                ->whereBetween('period_date', [$monthStart, $monthEnd])
                ->sum('amount');

            // Per-report-type breakdown (so daily/weekly/monthly are all visible)
            $typeRows = \App\Models\StaffReportPenalty::withoutGlobalScopes()
                ->where('user_id', $user->id)->where('waived', false)
                ->whereBetween('period_date', [$monthStart, $monthEnd])
                ->selectRaw('report_type, COUNT(*) as c, SUM(amount) as total')
                ->groupBy('report_type')->get()->keyBy('report_type');
            $byType = collect(['daily', 'weekly', 'monthly'])->map(fn ($t) => [
                'report_type' => $t,
                'count'       => (int) ($typeRows[$t]->c ?? 0),
                'total'       => round((float) ($typeRows[$t]->total ?? 0), 2),
            ])->values();

            $staffPenalties = [
                'month_label' => now()->format('M Y'),
                'month_total' => round((float) $monthTotal, 2),
                'by_type'     => $byType,
                'count_this_month' => \App\Models\StaffReportPenalty::withoutGlobalScopes()
                    ->where('user_id', $user->id)->where('waived', false)
                    ->whereBetween('period_date', [$monthStart, $monthEnd])->count(),
                'items' => $rows->map(fn ($p) => [
                    'id'           => $p->id,
                    'report_type'  => $p->report_type,
                    'penalty_type' => $p->penalty_type,
                    'period_date'  => $p->period_date->format('Y-m-d'),
                    'amount'       => round((float) $p->amount, 2),
                    'notes'        => $p->notes,
                ])->values(),
            ];
        }

        return response()->json([
            'staff_penalties' => $staffPenalties,
            'hosting_domains' => $hostingDomains,
            'total_expenses' => $totalExpenses !== null ? round((float) $totalExpenses, 2) : null,
            'total_receivable' => $can('dashboard.total_receivable') ? round($totalReceivable, 2) : null,
            'total_received' => $can('dashboard.total_received') ? round($totalReceived, 2) : null,
            'outstanding' => $can('dashboard.outstanding') ? round($totalReceivable - $totalReceived, 2) : null,
            'overdue_invoices' => $overdueInvoices,
            'overdue_bills' => $overdueBills,
            'total_clients'           => $totalClients,
            'total_whatsapp_contacts' => $totalWhatsappContacts,
            'total_field_visits'      => $totalFieldVisits,
            'total_documents' => $totalDocuments,
            'sms_balance' => $smsBalance,
            'sms_enabled' => $tenant?->sms_enabled ?? false,
            'recent_invoices' => $recentInvoices,
            'upcoming_bills' => $upcomingBills,
            'monthly_revenue' => $monthlyRevenue,
            'invoice_status_breakdown' => $invoiceStatusBreakdown,
            'payment_method_breakdown' => $paymentMethodBreakdown,
            'top_clients' => $topClients,
            'subscription_stats' => $subscriptionStats,
            'upcoming_renewals' => $upcomingRenewals,
            'statutory_stats' => $statutoryStats,
            'urgent_obligations' => $urgentObligations,
            'calendar' => $calendarData,
            'system_records' => $systemRecords,
        ]);
    }
}
