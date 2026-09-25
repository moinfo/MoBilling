<?php
// php tests/Manual/run_receive_payments.php  (live DB rolled back; notifications faked, no external calls)
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Http\Controllers\ReceivePaymentsController;
use App\Http\Middleware\CheckPermission;
use App\Models\{Client, ClientCredit, ClientSubscription, Document, PaymentIn, ProductService, RecurringInvoiceLog, Tenant, User};
use App\Notifications\PaymentReceiptNotification;
use App\Services\{OfflinePaymentService, PaymentMessageParser};
use Illuminate\Http\{Request, UploadedFile};
use Illuminate\Support\Facades\{Cache, DB, Http, Notification, Storage};

Http::preventStrayRequests();
Notification::fake();
$fail = 0;
function ok($c, $m) { global $fail; if (!$c) { $fail++; echo "FAIL $m\n"; } else echo "PASS $m\n"; }
function call(User $u, string $m, array $d = [], array $files = [], string $arg = null) {
    auth()->setUser($u);
    $rq = Request::create('/x', 'POST', $d, [], $files); $rq->setUserResolver(fn () => $u); app()->instance('request', $rq);
    try { $r = $arg !== null ? app(ReceivePaymentsController::class)->$m($rq, $arg) : app(ReceivePaymentsController::class)->$m($rq); }
    catch (\Illuminate\Validation\ValidationException $e) { return response()->json(['message' => 'validation', 'errors' => $e->errors()], 422); }
    return $r;
}
function j($r) { return $r->getData(true); }

// ---- parser samples (no DB)
$p = PaymentMessageParser::parse('QGH7X8K2LM Confirmed. Tsh55,000.00 received from JOHN DOE 255712345678 on 12/9/26 at 10:15 AM. New balance is Tsh 1,200,000.00');
ok($p['amount'] == 55000 && $p['reference'] === 'QGH7X8K2LM' && $p['phone'] === '255712345678' && $p['name'] === 'John Doe', 'parse M-Pesa');
$p = PaymentMessageParser::parse('Umepokea TSh 55,000 kutoka 255712345678 - JOHN DOE. Kumbukumbu: 12345678901. Salio jipya TSh 900,000');
ok($p['amount'] == 55000 && $p['reference'] === '12345678901' && $p['phone'] === '255712345678' && $p['name'] === 'John Doe', 'parse Tigo Pesa');
$p = PaymentMessageParser::parse('Umepokea Tsh55,000.00 kutoka kwa 0684123456 JUMA ALLY. Muamala ID: CI260912.1015.A12345. Salio Tsh 5,000');
ok($p['amount'] == 55000 && $p['reference'] === 'CI260912.1015.A12345' && $p['phone'] === '255684123456' && $p['name'] === 'Juma Ally', 'parse Airtel Money');
$p = PaymentMessageParser::parse('HaloPesa: Umepokea TSh 55,000 kutoka kwa 0622111222 MARY JOHN tarehe 12/09/2026. Ref: HP1234567');
ok($p['amount'] == 55000 && $p['reference'] === 'HP1234567' && $p['phone'] === '255622111222' && $p['name'] === 'Mary John', 'parse HaloPesa');
$p = PaymentMessageParser::parse('Credit alert: TZS 1,250,000.50 credited to A/C xxxx1234 on 12-09-2026. Narration: INV-2026-0012 JOHN DOE. Ref: FT26255ABCDE. Avail bal TZS 2,000,000.00');
ok($p['amount'] == 1250000.5 && $p['reference'] === 'FT26255ABCDE' && $p['invoice_number'] === 'INV-2026-0012', 'parse bank alert');
$p = PaymentMessageParser::parse('hello, nimelipa jana');
ok($p['amount'] === null && $p['reference'] === null && $p['phone'] === null, 'parse garbage -> nulls');
ok(PaymentMessageParser::parse('')['amount'] === null, 'parse empty');

DB::beginTransaction();
try {
    $tenantA = Tenant::withoutGlobalScopes()->where('name', 'MoBilling Test Co')->firstOrFail();
    $tenantB = Tenant::withoutGlobalScopes()->where('id', '!=', $tenantA->id)->firstOrFail();
    $staff = User::withoutGlobalScopes()->where('tenant_id', $tenantA->id)->whereHas('role', fn ($q) => $q->where('name', 'admin'))->get()->first(fn ($u) => !$u->isSuperAdmin() && $u->hasPermission('payments_in.create'))
        ?? User::withoutGlobalScopes()->where('tenant_id', $tenantA->id)->firstOrFail();
    auth()->setUser($staff);
    $tenantA->refresh();
    $tenantA->payment_methods = [['value' => 'bank', 'label' => 'Bank'], ['value' => 'mpesa', 'label' => 'Lipa Namba'], ['value' => 'pesapal', 'label' => 'Pesapal'], ['value' => 'cash', 'label' => 'Cash']];
    $tenantA->save(); $staff->unsetRelation('tenant');

    $cA = Client::create(['name' => 'RP Client A TEST', 'phone' => '255700000501', 'email' => 'rpa@example.test', 'status' => 'active']);
    $cB = Client::create(['name' => 'RP Client B TEST', 'phone' => '255700000502', 'email' => 'rpb@example.test', 'status' => 'active']);
    $n = 0;
    $mk = function ($client, $total, $due, $status = 'sent', $date = null) use ($tenantA, &$n) {
        $n++;
        $d = Document::create(['client_id' => $client->id, 'type' => 'invoice', 'document_number' => 'RPT-' . uniqid() . $n, 'date' => $date ?? '2026-01-01', 'due_date' => $due, 'subtotal' => $total, 'tax_amount' => 0, 'total' => $total, 'status' => $status]);
        return $d;
    };
    $d1 = $mk($cA, 100000, '2026-02-01'); $d2 = $mk($cA, 50000, '2026-03-01'); $d3 = $mk($cA, 30000, '2026-04-01', 'overdue');
    $dPaid = $mk($cA, 999, '2026-01-01', 'paid'); $dCan = $mk($cA, 999, '2026-01-01', 'cancelled'); $dDraft = $mk($cA, 999, '2026-01-01', 'draft');
    $dB = $mk($cB, 777, '2026-05-01');
    $foreignClient = Client::withoutGlobalScopes()->create(['tenant_id' => $tenantB->id, 'name' => 'Foreign TEST', 'phone' => '255700000599', 'status' => 'active']);
    $foreignDoc = Document::withoutGlobalScopes()->create(['tenant_id' => $tenantB->id, 'client_id' => $foreignClient->id, 'type' => 'invoice', 'document_number' => 'RPT-F' . uniqid(), 'date' => '2026-01-01', 'due_date' => '2026-01-05', 'subtotal' => 5, 'tax_amount' => 0, 'total' => 5, 'status' => 'sent']);

    // BelongsToTenant stamps the acting user's tenant on create: re-home the foreign rows explicitly
    DB::table('clients')->where('id', $foreignClient->id)->update(['tenant_id' => $tenantB->id]);
    DB::table('documents')->where('id', $foreignDoc->id)->update(['tenant_id' => $tenantB->id]);

    // ---- listing
    $r = j(call($staff, 'invoices', ['search' => 'RP Client A']));
    $ids = collect($r['data'])->pluck('id')->all();
    ok($ids === [$d1->id, $d2->id, $d3->id], 'listing: only unpaid of client, oldest due first (paid/cancelled/draft excluded)');
    ok($r['data'][0]['balance_due'] == 100000 && $r['data'][0]['paid_amount'] == 0, 'listing: balance/paid fields');
    $tt = j(call($staff, 'invoices', ['search' => $foreignDoc->document_number])); ok(count($tt['data']) === 0, 'listing: tenant isolation');
    ok(count(j(call($staff, 'invoices', ['search' => $d1->document_number]))['data']) === 1, 'search by invoice number');
    ok(collect(j(call($staff, 'invoices', ['amount' => 50000]))['data'])->pluck('id')->contains($d2->id), 'search by amount');
    ok(collect(j(call($staff, 'invoices', ['phone' => '0700000502']))['data'])->pluck('id')->all() === [$dB->id], 'filter by phone');
    ok(collect(j(call($staff, 'invoices', ['search' => '0700000502']))['data'])->pluck('id')->contains($dB->id), 'search by phone digits');
    ok(count(j(call($staff, 'invoices', ['client_id' => $cA->id, 'overdue' => 1]))['data']) === 3, 'overdue filter (due dates in the past)');
    ok(collect(j(call($staff, 'invoices', ['client_id' => $cA->id, 'date_from' => '2026-02-15', 'date_to' => '2026-03-15']))['data'])->pluck('id')->all() === [$d2->id], 'due date range');
    ok(j(call($staff, 'invoices', ['client_id' => $cA->id, 'per_page' => 2]))['last_page'] === 2, 'pagination');

    // ---- options
    $o = j(call($staff, 'options'));
    $vals = collect($o['methods'])->pluck('value')->all();
    ok($vals === ['bank', 'mpesa', 'cash'] && $o['methods'][0]['reference_required'] && !$o['methods'][2]['reference_required'], 'options hide pesapal; ref required for bank/mobile only');

    $post = fn ($d, $files = []) => call($staff, 'store', $d + ['payment_date' => now()->toDateString(), 'send_receipt' => 1], $files);
    $base = fn ($ids, $amt, $ref, $extra = []) => array_merge(['invoice_ids' => $ids, 'amount' => $amt, 'payment_method' => 'mpesa', 'reference' => $ref], $extra);

    // ---- partial
    $r = $post($base([$d1->id], 40000, 'PART1AAA'));
    ok($r->getStatusCode() === 201 && j($r)['invoices'][0]['status'] === 'partial' && j($r)['invoices'][0]['balance_after'] == 60000, 'partial payment -> partial, new balance 60000');
    ok($d1->fresh()->status === 'partial', 'invoice status partial persisted');
    $pi = PaymentIn::find(j($r)['payment_ids'][0]);
    ok($pi->received_by === $staff->id && $pi->tenant_id === $tenantA->id && $pi->reference === 'PART1AAA', 'received_by/tenant/reference stored');
    ok(Notification::sent($cA, PaymentReceiptNotification::class)->count() === 1, 'receipt notification sent (faked)');

    // ---- validation
    ok($post($base([$d1->id], 10, ''))->getStatusCode() === 422, 'reference required for mobile money');
    ok($post($base([$d1->id], 10, 'X1', ['payment_method' => 'pesapal']))->getStatusCode() === 422, 'pesapal method refused');
    ok($post($base([$d1->id], 10, 'X2', ['payment_method' => 'card']))->getStatusCode() === 422, 'card method refused');
    $fut = call($staff, 'store', $base([$d1->id], 10, 'X3') + ['payment_date' => now()->addDay()->toDateString()]);
    ok($fut->getStatusCode() === 422, 'future date refused');
    ok($post($base([$d1->id], 0, 'X4'))->getStatusCode() === 422, 'zero amount refused');
    ok($post(['invoice_ids' => [$d1->id], 'amount' => 100, 'payment_method' => 'cash'])->getStatusCode() === 201, 'cash needs no reference');
    ok($d1->fresh()->payments()->count() === 2, 'no payment rows created by refused calls');

    // ---- excess
    $r = $post($base([$d1->id], 70000, 'EXC1AAA'));
    ok($r->getStatusCode() === 422 && j($r)['code'] === 'exceeds_balance', 'excess refused without flag');
    ok($d1->fresh()->payments()->count() === 2 && (float) $cA->fresh()->credit_balance == 0, 'refusal wrote nothing');

    // ---- full payment + subscription activation
    $prod = ProductService::create(['type' => 'service', 'name' => 'RP Prod TEST', 'price' => 1, 'tax_percent' => 0, 'unit' => 'pcs', 'billing_cycle' => 'yearly', 'is_active' => true]);
    $sub = ClientSubscription::create(['client_id' => $cA->id, 'product_service_id' => $prod->id, 'label' => 'x', 'quantity' => 1, 'start_date' => '2025-01-01', 'expire_date' => '2026-01-01', 'status' => 'pending']);
    RecurringInvoiceLog::create(['client_id' => $cA->id, 'product_service_id' => $prod->id, 'client_subscription_id' => $sub->id, 'document_id' => $d2->id, 'next_bill_date' => '2026-01-01']);
    $r = $post($base([$d2->id], 50000, 'FULL1AAA'));
    ok($r->getStatusCode() === 201 && $d2->fresh()->status === 'paid', 'full payment -> paid');
    ok($sub->fresh()->status === 'active' && $sub->fresh()->expire_date->format('Y') === '2027', 'subscription activated + advanced');

    // ---- paid / cancelled refusal
    ok($post($base([$d2->id], 5, 'PAIDX1'))->getStatusCode() === 409, 'paid invoice -> 409');
    ok($post($base([$dCan->id], 5, 'CANX1'))->getStatusCode() === 409, 'cancelled invoice -> 409');
    ok($post($base([$dDraft->id], 5, 'DRAFTX1'))->getStatusCode() === 409, 'draft invoice -> 409');
    ok($post($base([$foreignDoc->id], 5, 'FOREIGN1'))->getStatusCode() === 404, 'other tenant invoice -> 404');
    ok($post($base([$d3->id, $dB->id], 5, 'MIX1AAA'))->getStatusCode() === 422, 'split across clients refused');

    // ---- duplicate reference guard
    $r = $post($base([$d3->id], 1000, ' part1aaa '));
    ok($r->getStatusCode() === 409 && j($r)['code'] === 'duplicate_reference', 'same reference (case/trim-insensitive) + method -> 409');
    $r = $post($base([$d3->id], 1000, 'PART1AAA', ['payment_method' => 'bank']));
    ok($r->getStatusCode() === 201, 'same reference on a different method is allowed');
    $r = $post($base([$d3->id], 1000, 'PART1AAA', ['confirm_different' => 1]));
    ok($r->getStatusCode() === 201, 'override with confirm_different records it');
    // old (>90 days) references do not block
    $old = PaymentIn::find(j($r)['payment_ids'][0]); DB::table('payments_in')->where('reference', 'PART1AAA')->update(['created_at' => now()->subDays(91)]);
    ok($post($base([$d3->id], 1000, 'part1aaa', ['payment_method' => 'mpesa']))->getStatusCode() === 201, 'reference older than 90 days does not block');

    // ---- 10-minute same-amount warning
    $r = $post($base([$d3->id], 1000, 'SAMEAMT2'));
    ok($r->getStatusCode() === 409 && j($r)['code'] === 'recent_same_amount', 'same amount within 10 minutes -> warning 409');
    ok($post($base([$d3->id], 1000, 'SAMEAMT2', ['confirm_different' => 1]))->getStatusCode() === 201, 'warning overridden');

    // ---- split across invoices, oldest first
    $s1 = $mk($cB, 20000, '2026-01-10'); $s2 = $mk($cB, 30000, '2026-01-05'); $s3 = $mk($cB, 40000, '2026-01-20');
    $r = $post($base([$s3->id, $s1->id, $s2->id], 60000, 'SPLIT1AAA'));
    $inv = j($r)['invoices'];
    ok($r->getStatusCode() === 201 && count($inv) === 3, 'split creates 3 allocations');
    ok($inv[0]['document_number'] === $s2->document_number && $inv[0]['amount'] == 30000 && $inv[0]['status'] === 'paid', 'oldest due (s2) paid first');
    ok($inv[1]['document_number'] === $s1->document_number && $inv[1]['amount'] == 20000 && $inv[1]['status'] === 'paid', 's1 second');
    ok($inv[2]['document_number'] === $s3->document_number && $inv[2]['amount'] == 10000 && $inv[2]['status'] === 'partial', 's3 partial with remainder');
    $rows = PaymentIn::whereIn('document_id', [$s1->id, $s2->id, $s3->id])->get();
    ok($rows->count() === 3 && $rows->sum('amount') == 60000 && $rows->every(fn ($x) => $x->reference === 'SPLIT1AAA' && str_contains($x->notes, 'split from ref SPLIT1AAA')), 'one PaymentIn each, shared ref + split note, total = entered');
    // split with excess
    $s4 = $mk($cB, 1000, '2026-06-01'); $s5 = $mk($cB, 2000, '2026-06-02');
    $r = $post($base([$s4->id, $s5->id], 3500, 'SPLIT2AAA'));
    ok($r->getStatusCode() === 422 && j($r)['code'] === 'exceeds_balance', 'split excess refused');
    $r = $post($base([$s4->id, $s5->id], 3500, 'SPLIT2AAA', ['allow_excess' => 1]));
    ok($r->getStatusCode() === 201 && j($r)['excess_credit'] == 500 && (float) $cB->fresh()->credit_balance == 500, 'excess recorded as client credit');
    ok(ClientCredit::withoutGlobalScopes()->where('client_id', $cB->id)->where('type', 'deposit')->where('amount', 500)->exists(), 'credit ledger row');
    // undo refuses when credit created
    $firstPay = PaymentIn::where('document_id', $s4->id)->first();
    $u = call($staff, 'undo', [], [], $firstPay->id);
    ok($u->getStatusCode() === 422, 'undo refused when payment created client credit');

    // ---- idempotency
    $cKey = 'key-' . uniqid();
    $i1 = $mk($cA, 9000, '2026-07-01');
    $r1 = $post($base([$i1->id], 2000, 'IDEM1AAA', ['idempotency_key' => $cKey]));
    $r2 = $post($base([$i1->id], 2000, 'IDEM1AAA', ['idempotency_key' => $cKey]));
    ok($r1->getStatusCode() === 201 && $r2->getStatusCode() === 200 && j($r2)['replayed'] === true && j($r1)['payment_ids'] === j($r2)['payment_ids'], 'same idempotency key returns first result');
    ok(PaymentIn::where('document_id', $i1->id)->count() === 1, 'idempotent replay created no second payment');

    // ---- attachments
    Storage::fake('local');
    $i2 = $mk($cA, 9000, '2026-07-02');
    $bad = UploadedFile::fake()->create('x.exe', 10, 'application/x-msdownload');
    ok($post($base([$i2->id], 100, 'ATT1AAA'), ['proof' => $bad])->getStatusCode() === 422 && PaymentIn::where('document_id', $i2->id)->count() === 0, 'bad attachment type refused');
    $big = UploadedFile::fake()->create('big.pdf', 6000, 'application/pdf');
    ok($post($base([$i2->id], 100, 'ATT2AAA'), ['proof' => $big])->getStatusCode() === 422, 'oversize attachment refused');
    $good = UploadedFile::fake()->image('slip.png', 20, 20);
    $r = $post($base([$i2->id], 100, 'ATT3AAA'), ['proof' => $good]);
    $ap = PaymentIn::find(j($r)['payment_ids'][0])->attachment_path;
    ok($r->getStatusCode() === 201 && str_starts_with($ap, "payment-proofs/{$tenantA->id}/") && Storage::disk('local')->exists($ap), 'valid proof stored on private disk');

    // ---- undo window
    $pid = j($r)['payment_ids'][0];
    $rec = j(call($staff, 'recent'));
    $row = collect($rec['data'])->firstWhere('id', $pid);
    ok($row && $row['undoable'] === $staff->hasPermission('payments_in.delete'), 'recent list shows payment; undoable per permission');
    $u = call($staff, 'undo', [], [], $pid);
    ok($u->getStatusCode() === 200 && !PaymentIn::find($pid) && $i2->fresh()->status === 'overdue' && !Storage::disk('local')->exists($ap), 'undo deletes payment, restores status, removes proof');
    $r = $post($base([$i2->id], 100, 'UNDO2AAA')); $pid2 = j($r)['payment_ids'][0];
    DB::table('payments_in')->where('id', $pid2)->update(['created_at' => now()->subMinutes(20)]);
    ok(call($staff, 'undo', [], [], $pid2)->getStatusCode() === 403, 'undo after 15 minutes refused');
    $other = User::withoutGlobalScopes()->where('tenant_id', $tenantA->id)->where('id', '!=', $staff->id)->first();
    if ($other) {
        $r = $post($base([$i2->id], 101, 'UNDO3AAA')); $pid3 = j($r)['payment_ids'][0];
        ok(call($other, 'undo', [], [], $pid3)->getStatusCode() === 403, "cannot undo someone else's payment");
    }

    // ---- parse endpoint suggestions (never records)
    $before = PaymentIn::count();
    $r = j(call($staff, 'parse', ['text' => "ABCD12345 Confirmed. Tsh777.00 received from RP CLIENT B 0700000502"]));
    ok($r['parsed']['amount'] == 777 && collect($r['suggestions'])->pluck('id')->contains($dB->id) && PaymentIn::count() === $before, 'parse endpoint suggests invoice, records nothing');

    // ---- permissions
    $has = fn ($u) => $u->hasAnyPermission(['payments_in.create']);
    $noPerm = User::withoutGlobalScopes()->whereNotNull('role_id')->limit(400)->get()->first(fn ($u) => !$u->isSuperAdmin() && !$has($u));
    if ($noPerm) {
        $rq = Request::create('/x'); $rq->setUserResolver(fn () => $noPerm);
        ok((new CheckPermission())->handle($rq, fn () => response('ok'), 'payments_in.create')->getStatusCode() === 403, 'user without payments_in.create gets 403');
    } else echo "SKIP no user without payments_in.create\n";
    $routes = collect(app('router')->getRoutes()->getRoutes())->filter(fn ($rt) => str_starts_with($rt->uri(), 'api/receive-payments') || str_starts_with($rt->uri(), 'receive-payments'));
    ok($routes->count() === 7 && $routes->every(fn ($rt) => collect($rt->gatherMiddleware())->contains(fn ($m) => str_starts_with($m, 'permission:payments_in.'))), 'all 7 routes gated by payments_in.* permissions');
} catch (\Throwable $e) {
    $fail++; echo "EXCEPTION " . $e->getMessage() . ' @ ' . $e->getFile() . ':' . $e->getLine() . "\n";
} finally {
    DB::rollBack();
}
echo $fail ? "\n$fail FAILURES\n" : "\nALL PASS\n";
exit($fail ? 1 : 0);
