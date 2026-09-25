<?php

namespace App\Http\Controllers;

use App\Helpers\PhoneHelper;
use App\Models\Client;
use App\Models\Document;
use App\Models\PaymentIn;
use App\Services\OfflinePaymentException;
use App\Services\OfflinePaymentService;
use App\Services\PaymentMessageParser;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

/** Staff "Receive payments" page: unpaid invoices + offline payment recording. Permission group: payments_in.*. */
class ReceivePaymentsController extends Controller
{
    public function __construct(private OfflinePaymentService $service) {}

    public function options(Request $request)
    {
        $user = $request->user();

        return response()->json([
            'methods' => OfflinePaymentService::methodsFor($user->tenant),
            'can_undo' => $user->hasPermission('payments_in.delete'),
            'undo_minutes' => OfflinePaymentService::UNDO_MINUTES,
        ]);
    }

    public function invoices(Request $request)
    {
        $request->validate([
            'search' => 'nullable|string|max:100', 'client_id' => 'nullable|uuid', 'overdue' => 'nullable|boolean',
            'date_from' => 'nullable|date', 'date_to' => 'nullable|date', 'per_page' => 'nullable|integer|min:1|max:100',
            'amount' => 'nullable|numeric', 'phone' => 'nullable|string|max:30',
        ]);
        $tenantId = $request->user()->tenant_id;
        $bal = OfflinePaymentService::balanceSql();
        $q = OfflinePaymentService::unpaidQuery($tenantId);

        if ($request->filled('client_id')) {
            $q->where('documents.client_id', $request->client_id);
        }
        if ($request->boolean('overdue')) {
            $q->where(fn ($w) => $w->where('documents.status', 'overdue')->orWhere('documents.due_date', '<', now()->toDateString()));
        }
        if ($request->filled('date_from')) {
            $q->where('documents.due_date', '>=', $request->date_from);
        }
        if ($request->filled('date_to')) {
            $q->where('documents.due_date', '<=', $request->date_to);
        }
        if ($request->filled('amount')) {
            $amt = round((float) $request->amount, 2);
            $q->where(fn ($w) => $w->whereRaw("ROUND({$bal}, 2) = ?", [$amt])->orWhere('documents.total', $amt));
        }
        if ($request->filled('phone')) {
            $q->whereHas('client', fn ($c) => PhoneHelper::wherePhone($c->withoutGlobalScopes()->where('clients.tenant_id', $tenantId), 'clients.phone', $request->phone));
        }
        if ($request->filled('search')) {
            OfflinePaymentService::applySearch($q, $request->search, $tenantId);
        }

        $page = $q->paginate($request->integer('per_page', 20));

        $today = now()->toDateString();
        $page->getCollection()->transform(function (Document $d) use ($today) {
            $paid = round((float) $d->paid_sum - (float) $d->refund_sum, 2);
            $balance = round((float) $d->total - $paid, 2);

            return [
                'id' => $d->id, 'document_number' => $d->document_number, 'status' => $d->status,
                'date' => $d->date?->format('Y-m-d'), 'due_date' => $d->due_date?->format('Y-m-d'),
                'is_overdue' => $d->status === 'overdue' || ($d->due_date && $d->due_date->format('Y-m-d') < $today),
                'total' => (float) $d->total, 'paid_amount' => $paid, 'balance_due' => $balance,
                'client' => $d->client ? ['id' => $d->client->id, 'name' => $d->client->name, 'phone' => $d->client->phone, 'credit_balance' => (float) $d->client->credit_balance] : null,
            ];
        });

        return response()->json($page);
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'invoice_ids' => 'required|array|min:1|max:25', 'invoice_ids.*' => 'uuid',
            'amount' => 'required|numeric|min:0.01|max:999999999',
            'payment_method' => 'required|string|max:50',
            'payment_date' => 'required|date|before_or_equal:today',
            'reference' => 'nullable|string|max:255', 'notes' => 'nullable|string|max:1000',
            'send_receipt' => 'nullable|boolean', 'allow_excess' => 'nullable|boolean', 'confirm_different' => 'nullable|boolean',
            'idempotency_key' => 'nullable|string|max:100',
            'proof' => 'nullable|file|max:5120',
        ]);

        try {
            $r = $this->service->record($request->user(), $data['invoice_ids'], (float) $data['amount'], [
                'method' => $data['payment_method'], 'payment_date' => $data['payment_date'],
                'reference' => $data['reference'] ?? null, 'notes' => $data['notes'] ?? null,
                'send_receipt' => $request->boolean('send_receipt', true), 'allow_excess' => $request->boolean('allow_excess'),
                'confirm_different' => $request->boolean('confirm_different'), 'idempotency_key' => $data['idempotency_key'] ?? null,
            ], $request->file('proof'));
        } catch (OfflinePaymentException $e) {
            return response()->json(['message' => $e->getMessage(), 'code' => $e->errorCode] + $e->extra, $e->status);
        }

        return response()->json([
            'message' => 'Payment recorded.', 'replayed' => $r['replayed'], 'invoices' => $r['invoices'],
            'excess_credit' => $r['excess_credit'],
            'payment_ids' => collect($r['payments'])->pluck('id')->all(),
        ], $r['replayed'] ? 200 : 201);
    }

    /** Payments recorded by the current user in the last 24h. */
    public function recent(Request $request)
    {
        $user = $request->user();
        $canUndo = $user->hasPermission('payments_in.delete');
        $rows = PaymentIn::withoutGlobalScopes()->where('tenant_id', $user->tenant_id)->where('received_by', $user->id)
            ->where('created_at', '>=', now()->subDay())->with(['client' => fn ($c) => $c->withoutGlobalScopes()->select('id', 'name'),
                'document' => fn ($d) => $d->withoutGlobalScopes()->select('id', 'document_number')])
            ->latest('created_at')->limit(50)->get();

        return response()->json(['data' => $rows->map(fn ($p) => [
            'id' => $p->id, 'amount' => (float) $p->amount, 'payment_method' => $p->payment_method, 'reference' => $p->reference,
            'payment_date' => $p->payment_date->format('Y-m-d'), 'created_at' => $p->created_at,
            'client_name' => $p->client?->name, 'document_number' => $p->document?->document_number,
            'undoable' => $canUndo && $p->created_at->gte(now()->subMinutes(OfflinePaymentService::UNDO_MINUTES)),
            'has_proof' => (bool) $p->attachment_path,
        ])->values()]);
    }

    public function undo(Request $request, string $payment)
    {
        try {
            $doc = $this->service->undo($request->user(), $payment);
        } catch (OfflinePaymentException $e) {
            return response()->json(['message' => $e->getMessage(), 'code' => $e->errorCode], $e->status);
        }

        return response()->json(['message' => 'Payment undone.', 'status' => $doc?->status]);
    }

    public function proof(Request $request, string $payment)
    {
        $p = PaymentIn::withoutGlobalScopes()->where('tenant_id', $request->user()->tenant_id)->whereKey($payment)->first();
        if (!$p || !$p->attachment_path || !str_starts_with($p->attachment_path, 'payment-proofs/') || !Storage::disk('local')->exists($p->attachment_path)) {
            return response()->json(['message' => 'Not found'], 404);
        }

        return Storage::disk('local')->download($p->attachment_path);
    }

    /** Parse a pasted SMS / bank alert and suggest matching invoices. Never records anything. */
    public function parse(Request $request)
    {
        $request->validate(['text' => 'required|string|max:2000']);
        $parsed = PaymentMessageParser::parse($request->text);
        $tenantId = $request->user()->tenant_id;
        $bal = OfflinePaymentService::balanceSql();

        $q = Document::withoutGlobalScopes()->where('documents.tenant_id', $tenantId)->whereNull('documents.deleted_at')
            ->where('documents.type', 'invoice')->whereIn('documents.status', OfflinePaymentService::UNPAID)->whereRaw("({$bal}) > 0.005");
        $q->where(function ($w) use ($parsed, $bal, $tenantId) {
            $any = false;
            if ($parsed['amount']) {
                $w->orWhereRaw("ROUND({$bal}, 2) = ?", [round($parsed['amount'], 2)]); $any = true;
            }
            if ($parsed['phone']) {
                $w->orWhereHas('client', fn ($c) => PhoneHelper::wherePhone($c->withoutGlobalScopes()->where('clients.tenant_id', $tenantId), 'clients.phone', $parsed['phone'])); $any = true;
            }
            if ($parsed['name']) {
                $w->orWhereHas('client', fn ($c) => $c->withoutGlobalScopes()->where('clients.tenant_id', $tenantId)->where('clients.name', 'like', '%' . addcslashes($parsed['name'], '%_\\') . '%')); $any = true;
            }
            if ($parsed['invoice_number']) {
                $w->orWhere('documents.document_number', 'like', '%' . addcslashes($parsed['invoice_number'], '%_\\')); $any = true;
            }
            if (!$any) {
                $w->whereRaw('1 = 0');
            }
        });
        $suggestions = $q->with(['client' => fn ($c) => $c->withoutGlobalScopes()->select('id', 'name', 'phone')])
            ->orderBy('documents.due_date')->limit(10)->get()->map(fn ($d) => [
                'id' => $d->id, 'document_number' => $d->document_number, 'client_name' => $d->client?->name,
                'balance_due' => round((float) $d->balance_due, 2),
            ])->all();

        return response()->json(['parsed' => $parsed, 'suggestions' => $suggestions]);
    }
}
