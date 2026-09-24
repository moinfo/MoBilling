<?php
// php tests/Manual/run_linode_billing.php  (live DB, everything rolled back; Linode + notifications + queue faked)
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Http\Controllers\LinodeController;
use App\Http\Controllers\Portal\PortalSubscriptionController;
use App\Models\{Client, ClientSubscription, Document, LinodeAccount, LinodeAuditLog, LinodeResource, ProductService, RecurringInvoiceLog, Tenant, User};
use App\Services\Linode\LinodeBilling;
use App\Services\RecurringInvoiceService;
use App\Services\SubscriptionActivationService;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\{DB, Http, Notification, Queue};

$fail = 0;
function ok($c, $m) { global $fail; if (!$c) { $fail++; echo "FAIL $m\n"; } else echo "PASS $m\n"; }
function bind(array $d) { app()->instance('request', Request::create('/x', 'POST', $d)); return app('request'); }
function refused(callable $f): ?string { try { $f(); return null; } catch (\DomainException $e) { return $e->getMessage(); } }

Http::fake();          // any Linode/HTTP call would be recorded
Notification::fake();
Queue::fake();

DB::beginTransaction();
try {
    Carbon::setTestNow('2026-09-24 10:00:00');
    $tenantA = Tenant::withoutGlobalScopes()->where('name', 'MoBilling Test Co')->firstOrFail();
    $userA = User::withoutGlobalScopes()->where('tenant_id', $tenantA->id)->firstOrFail();
    auth()->login($userA);

    $acct = new LinodeAccount(['label' => 'T', 'token' => 'lin_SECRET_TOKEN_abcdefghijklmnopqrstuvwxyz1234', 'token_hint' => '1234', 'status' => 'active']);
    $acct->tenant_id = $tenantA->id; $acct->save();
    $mk = fn ($id, $label, $ip) => LinodeResource::create(['tenant_id' => $tenantA->id, 'linode_account_id' => $acct->id, 'type' => 'instance', 'remote_id' => $id, 'label' => $label, 'status' => 'running', 'region' => 'eu-central', 'plan' => 'g6-nanode-1', 'ipv4' => [$ip]]);
    $srv1 = $mk('1001', 'swedi-vps', '203.0.113.10');
    $srv2 = $mk('1002', 'other-vps', '203.0.113.11');
    $swedi = Client::create(['name' => 'Swedi Kasimu TEST', 'phone' => '255700000101', 'email' => 'swedi@example.test', 'status' => 'active']);
    $other = Client::create(['name' => 'Other TEST', 'phone' => '255700000102', 'email' => 'other@example.test', 'status' => 'active']);
    $prod = ProductService::create(['type' => 'service', 'name' => 'Linode Server - Yearly', 'price' => 500000, 'tax_percent' => 0, 'unit' => 'pcs', 'category' => 'Linode Servers', 'billing_cycle' => 'yearly', 'provisioning_type' => 'linode', 'portal_visible' => false, 'is_active' => true]);
    $svc = app(LinodeBilling::class);

    // ---- 1. already paid: start 2026-06-01, 600000, yearly
    $docsBefore = Document::count(); $logsBefore = RecurringInvoiceLog::count();
    $res = $svc->bill($srv1, ['client_id' => $swedi->id, 'product_service_id' => $prod->id, 'amount' => 600000, 'start_date' => '2026-06-01', 'mode' => 'paid_outside']);
    $sub = $res['subscription']->fresh();
    ok(Document::count() === $docsBefore && $res['document'] === null, 'already-paid: NO invoice created');
    ok(RecurringInvoiceLog::count() === $logsBefore, 'already-paid (past anchor): no log row needed');
    ok($sub->status === 'active' && $sub->start_date->toDateString() === '2026-06-01' && $sub->expire_date->toDateString() === '2027-06-01', 'start 2026-06-01, expire 2027-06-01, active');
    ok((float) $sub->recurring_amount === 600000.0 && ($sub->metadata['price_override'] ?? false) && $sub->metadata['linode_resource_id'] === $srv1->id && $sub->metadata['linode_ipv4'] === '203.0.113.10', 'recurring_amount 600000, override flag, metadata has server id/IP');
    ok($sub->label === 'swedi-vps 203.0.113.10', 'label defaults to server label + IP');
    $r1 = $srv1->fresh();
    ok($r1->client_subscription_id === $sub->id && $r1->client_id === $swedi->id, 'server linked to subscription and client');
    ok(LinodeAuditLog::where('action', 'resource.bill')->where('target', 'swedi-vps')->exists(), 'audit logged');

    // ---- engine selection simulation (real calculateNextBillDate + real exists-check semantics)
    $ref = new ReflectionMethod(RecurringInvoiceService::class, 'calculateNextBillDate'); $ref->setAccessible(true);
    $selected = function (string $day) use ($sub, $ref) {
        Carbon::setTestNow("$day 06:00:00");
        $s = ClientSubscription::with('productService')->find($sub->id);
        $eligible = ClientSubscription::where('status', 'active')->whereHas('productService', fn ($q) => $q->where('is_active', true)->whereNotNull('billing_cycle')->where('billing_cycle', '!=', 'once')->whereNull('invoice_day_of_month'))->where('id', $sub->id)->exists();
        $next = $ref->invoke(app(RecurringInvoiceService::class), $s->start_date, '1 year', Carbon::today());
        $logged = RecurringInvoiceLog::where('client_id', $s->client_id)->where('product_service_id', $s->product_service_id)->where('next_bill_date', $next->format('Y-m-d'))->exists();
        return $eligible && !$next->gt(Carbon::today()->addDays(30)) && !$logged ? $next->toDateString() : null;
    };
    ok($selected('2026-09-24') === null, 'engine does NOT bill today (current period not re-invoiced)');
    ok($selected('2027-04-30') === null && $selected('2027-05-01') === null, 'engine does not bill 32/31 days before renewal');
    ok($selected('2027-05-02') === '2027-06-01', 'engine bills on 2027-05-02 (30 days before 2027-06-01)');
    Carbon::setTestNow('2027-05-02 06:00:00');
    $prev = app(RecurringInvoiceService::class)->previewForSubscriptions([$sub->fresh()]);
    ok($prev['total'] == 600000.0 && $prev['due_date'] === '2027-06-01' && $prev['line_items'][0]['service_from'] === '2026-06-01' && $prev['line_items'][0]['service_to'] === '2027-05-31', 'renewal invoice previews 600000, due 2027-06-01, period 2026-06-01..2027-05-31');
    Carbon::setTestNow('2026-09-24 10:00:00');

    // ---- 2. double billing refused
    ok(str_contains((string) refused(fn () => $svc->bill($srv1, ['client_id' => $swedi->id, 'product_service_id' => $prod->id, 'amount' => 1, 'start_date' => '2026-06-01', 'mode' => 'paid_outside'])), 'already has an active subscription'), 'double-billing a server refused');
    ok(ClientSubscription::where('client_id', $swedi->id)->count() === 1, 'no second subscription created');

    // ---- 3. create invoice now
    $res2 = $svc->bill($srv2, ['client_id' => $other->id, 'product_service_id' => $prod->id, 'amount' => 600000, 'start_date' => '2026-09-24', 'mode' => 'invoice_now']);
    $doc = $res2['document']; $sub2 = $res2['subscription']->fresh();
    ok($doc && Document::where('client_id', $other->id)->where('type', 'invoice')->count() === 1 && (float) $doc->total === 600000.0 && $doc->status === 'sent', 'invoice-now: exactly one invoice, 600000, status sent');
    ok($sub2->status === 'pending' && $sub2->expire_date === null, 'invoice-now: subscription pending, expire unset until paid');
    ok(RecurringInvoiceLog::where('document_id', $doc->id)->where('client_subscription_id', $sub2->id)->exists(), 'invoice-now: log links invoice to subscription');
    ok($doc->items()->first()->price == 600000, 'invoice line price is the override amount');
    app(SubscriptionActivationService::class)->activateFor($doc);
    $sub2 = $sub2->fresh();
    ok($sub2->status === 'active' && $sub2->expire_date->toDateString() === '2027-09-24', 'paying the invoice activates and sets expire = start + 1 year');

    // ---- 4. link existing / unlink / guards
    $srv3 = $mk('1003', 'third-vps', '203.0.113.12');
    ok(str_contains((string) refused(fn () => $svc->link($srv3, $sub->id)), 'already linked'), 'cannot link a subscription already on another server');
    $svc->unlink($srv1);
    ok($srv1->fresh()->client_subscription_id === null && ClientSubscription::find($sub->id)->status === 'active', 'unlink removes only the link');
    $svc->link($srv3, $sub->id);
    ok($srv3->fresh()->client_subscription_id === $sub->id && $srv3->fresh()->client_id === $swedi->id, 'link existing subscription works');

    // ---- 5. suspend / cancel: no Linode call, nothing else
    Http::fake(); // reset recorder
    $sub = ClientSubscription::find($sub->id);
    $sub->update(['status' => 'suspended']);
    $sub->update(['status' => 'active']);
    $sub->update(['status' => 'cancelled']);
    ok(Http::recorded()->count() === 0, 'suspend/cancel/reactivate made ZERO HTTP calls (no Linode call)');
    ok(Queue::pushed(\App\Jobs\Hosting\SuspendHostingAccount::class)->isEmpty() && Queue::pushed(\App\Jobs\Hosting\ReactivateHostingAccount::class)->isEmpty() && Queue::pushed(\App\Jobs\Hosting\ProvisionHostingAccount::class)->isEmpty(), 'no hosting jobs dispatched');
    ok(LinodeAuditLog::where('action', 'subscription.status_changed')->where('request->client_subscription_id', $sub->id)->count() === 3, 'status changes only leave audit entries (staff alert)');
    ok($srv3->fresh()->status === 'running', 'server record untouched');

    // ---- 6. tenant isolation
    $tenantB = Tenant::withoutGlobalScopes()->where('id', '!=', $tenantA->id)->whereHas('users')->first() ?? Tenant::withoutGlobalScopes()->where('id', '!=', $tenantA->id)->firstOrFail();
    $userB = User::withoutGlobalScopes()->where('tenant_id', $tenantB->id)->firstOrFail();
    $srvId = $srv2->id; $clientAId = $other->id; $prodId = $prod->id;
    auth()->login($userB);
    $threw = false;
    try { $svc->bill(LinodeResource::withoutGlobalScopes()->find($srvId), ['client_id' => $clientAId, 'product_service_id' => $prodId, 'amount' => 5, 'start_date' => '2026-06-01', 'mode' => 'paid_outside']); }
    catch (\Throwable $e) { $threw = true; }
    ok($threw, "tenant B cannot bill tenant A's server");
    $r = app(LinodeController::class)->servers()->getData(true)['data'];
    ok(count($r) === LinodeResource::where('type', 'instance')->count() && collect($r)->pluck('id')->doesntContain($srvId), 'tenant B servers list excludes tenant A servers');
    auth()->login($userA);

    // ---- 7. portal listing: linked server shows for its client only
    $srv2 = $srv2->fresh();
    $portalCall = function (Client $c) {
        $req = Request::create('/x', 'GET'); $u = new User(); $u->client_id = $c->id; $req->setUserResolver(fn () => $u);
        return collect(app(PortalSubscriptionController::class)->index($req)->getData(true)['data']);
    };
    $rows = $portalCall($other);
    $row = $rows->firstWhere('id', $sub2->id);
    ok($row && ($row['linode_server']['name'] ?? null) === 'other-vps' && $row['linode_server']['ip'] === '203.0.113.11', "portal shows the client's server (name, IP, region)");
    ok(!str_contains(json_encode($row['linode_server']), 'token') && !isset($row['linode_server']['remote_id']), 'portal payload has no secrets/ids');
    ok(!str_contains(json_encode($portalCall($swedi)->all()), '203.0.113.11'), "other client's portal never shows that server");

    // ---- 8. product validation / portal catalog exclusion
    $rq = new \App\Http\Requests\StoreProductServiceRequest();
    ok(in_array('linode', explode(',', explode('in:none,whm_cpanel,', $rq->rules()['provisioning_type'])[1])), 'product validation accepts provisioning_type linode');
} catch (\Throwable $e) {
    $fail++; echo 'FAIL exception ' . $e->getMessage() . ' @' . $e->getFile() . ':' . $e->getLine() . "\n";
}
Carbon::setTestNow();
DB::rollBack();
echo $fail ? "$fail FAILED\n" : "ALL PASSED\n";
exit($fail ? 1 : 0);
