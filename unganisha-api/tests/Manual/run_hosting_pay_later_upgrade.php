<?php
// php tests/Manual/run_hosting_pay_later_upgrade.php
// Live DB, EVERY scenario rolled back. WHM is 100% faked (Http::fake on a fake host, preventStrayRequests);
// WhatsApp uses the bound fake; notifications faked. Never touches a real hosting account.
require __DIR__ . '/../../vendor/autoload.php';
require __DIR__ . '/WhatsappHostingManageTest.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Http\Controllers\Portal\PortalHostingController;
use App\Models\{Client, ClientSubscription, Document, HostingAccount, MosmsAccount, ProductService, ProvisioningLog, Server, Tenant, User, WhatsappRenewalSession};
use App\Services\Hosting\{BandwidthSuspensionService, PlanChangeService};
use App\Services\WhatsAppService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\{Cache, DB, Http, Notification};
use Tests\Manual\FakeWa;

$fail = 0;
function ok($c, $m) { global $fail; if (!$c) { $fail++; echo "FAIL $m\n"; } else echo "PASS $m\n"; }

const GB = 1073741824;
$whmCalls = [];
$whmState = ['pkg' => 'pkg_cur', 'used' => (int) (4.14 * GB)];
$pkgLimitsMb = ['pkg_cur' => 4096, 'pkg_big' => 20480, 'pkg_mid' => 4096, 'pkg_low' => 1024]; // pkg_unk deliberately absent
function fakeWhm() {
    global $whmCalls, $whmState, $pkgLimitsMb;
    Http::swap(new \Illuminate\Http\Client\Factory());
    Http::preventStrayRequests();
    Http::fake(function ($request) use (&$whmCalls, &$whmState, &$pkgLimitsMb) {
        $url = $request->url();
        if (!str_contains($url, 'bw-fake.invalid')) {
            return Http::response(['ok' => true], 200); // any other (non-WHM) request is faked too
        }
        preg_match('#/json-api/(\w+)#', $url, $m);
        $fn = $m[1];
        $whmCalls[] = $fn;
        $meta = ['metadata' => ['result' => 1, 'reason' => 'OK']];
        if ($fn === 'listpkgs') {
            $pkgs = [];
            foreach ($pkgLimitsMb as $n => $mb) { $pkgs[] = ['name' => $n, 'BWLIMIT' => (string) $mb]; }
            return Http::response($meta + ['data' => ['pkg' => $pkgs]], 200);
        }
        if ($fn === 'showbw') {
            $lim = ($pkgLimitsMb[$whmState['pkg']] ?? 5000) * 1048576;
            return Http::response($meta + ['data' => ['acct' => [['user' => 'bwuser', 'totalbytes' => $whmState['used'], 'limit' => $lim]]]], 200);
        }
        if ($fn === 'changepackage' && !empty($GLOBALS['failCp'])) {
            return Http::response(['metadata' => ['result' => 0, 'reason' => 'simulated failure']], 200);
        }
        if ($fn === 'changepackage') {
            parse_str(parse_url($url, PHP_URL_QUERY) ?? '', $q);
            $whmState['pkg'] = $q['pkg'] ?? $whmState['pkg'];
        }
        return Http::response($meta + ['data' => []], 200);
    });
}

$tenant = Tenant::withoutGlobalScopes()->where('name', 'MoBilling Test Co')->firstOrFail();
$staffUser = User::withoutGlobalScopes()->where('tenant_id', $tenant->id)->firstOrFail();

function scenario(string $title, callable $fn) {
    global $fail, $whmCalls, $whmState, $tenant, $staffUser;
    echo "== $title\n";
    DB::beginTransaction();
    try {
        auth()->login($staffUser);
        $whmCalls = []; $whmState = ['pkg' => 'pkg_cur', 'used' => (int) (4.14 * GB)]; $GLOBALS['failCp'] = false; config(['hosting.pay_later_upgrade_max' => 500000]);
        fakeWhm(); Notification::fake();
        $fn();
    } catch (\Throwable $e) {
        $fail++; echo "FAIL exception: " . $e->getMessage() . ' @' . basename($e->getFile()) . ':' . $e->getLine() . "\n";
    } finally {
        DB::rollBack();
        auth()->logout();
    }
}

function mkServer(): Server {
    global $tenant;
    $s = Server::create(['tenant_id' => $tenant->id, 'name' => 'bw-fake', 'hostname' => 'bw-fake.invalid', 'port' => 2087, 'username' => 'moinfote', 'api_token' => 'x', 'type' => 'whm', 'is_active' => true, 'verify_ssl' => false]);
    Cache::forget("whm_pkg_bw:{$s->id}");
    return $s;
}
function mkPlan(string $name, float $price, string $pkg): ProductService {
    global $tenant;
    return ProductService::create(['tenant_id' => $tenant->id, 'type' => 'service', 'name' => $name, 'price' => $price, 'category' => 'BW Test Group', 'billing_cycle' => 'yearly', 'provisioning_type' => 'whm_cpanel', 'is_active' => true, 'portal_visible' => true, 'cpanel_package' => $pkg]);
}
/** [client, account, currentPlan] — sub status/usage configurable. */
function mkAccount(string $status = 'suspended', string $subStatus = 'active', ?int $used = null, ?int $limit = null, string $domain = 'bwtest.example.test', ?string $phone = null): array {
    global $tenant;
    $server = mkServer();
    $client = Client::create(['tenant_id' => $tenant->id, 'name' => 'Bw Client ' . uniqid(), 'phone' => $phone ?? ('2557' . random_int(10000000, 99999999)), 'email' => uniqid() . '@example.test', 'status' => 'active']);
    $cur = mkPlan('BW Cur', 10000, 'pkg_cur');
    $sub = ClientSubscription::create(['tenant_id' => $tenant->id, 'client_id' => $client->id, 'product_service_id' => $cur->id, 'label' => $domain, 'start_date' => now()->subMonths(6), 'expire_date' => now()->addMonths(6), 'status' => $subStatus]);
    $acct = HostingAccount::create(['tenant_id' => $tenant->id, 'client_subscription_id' => $sub->id, 'server_id' => $server->id, 'domain' => $domain, 'cpanel_username' => 'bwuser', 'package' => 'pkg_cur', 'status' => $status, 'meta' => ['bw_used_bytes' => $used ?? (int) (4.14 * GB), 'bw_limit_bytes' => $limit ?? 4 * GB]]);
    return [$client, $acct, $cur];
}
function portalUser(Client $c, string $role = 'admin'): User {
    $u = new User(); $u->client_id = $c->id; $u->tenant_id = $c->tenant_id; $u->role = $role; return $u;
}
function portal(string $method, Client $c, HostingAccount $a, array $body = []) {
    $req = Request::create('/x', $method === 'show' || $method === 'upgradeOptions' ? 'GET' : 'POST', $body);
    $u = portalUser($c);
    $req->setUserResolver(fn () => $u);
    try {
        $res = app(PortalHostingController::class)->$method($req, $a->fresh());
        return [$res->getStatusCode(), $res->getData(true)];
    } catch (\Symfony\Component\HttpKernel\Exception\HttpException $e) {
        return [$e->getStatusCode(), ['message' => $e->getMessage()]];
    } catch (\Illuminate\Validation\ValidationException $e) {
        return [422, ['message' => json_encode($e->errors())]];
    }
}
function whmCount(string $fn): int { global $whmCalls; return count(array_filter($whmCalls, fn ($c) => $c === $fn)); }
$phone = \App\Helpers\PhoneHelper::normalize('255700000001');
function wa_boot() {
    global $tenant;
    config(['services.mosms.inbound_webhook_secret' => 'test-secret', 'services.mosms.inbound_rate_limit' => 100000, 'services.mosms.duplicate_window' => 0]);
    if (!MosmsAccount::withoutGlobalScopes()->where('tenant_id', $tenant->id)->where('mosms_tenant_id', 987654321)->exists()) {
        MosmsAccount::create(['tenant_id' => $tenant->id, 'mosms_tenant_id' => 987654321, 'email' => 'x@example.test', 'token' => 'x', 'sender' => 'x']);
    }
    FakeWa::$sent = [];
    app()->bind(WhatsAppService::class, fn () => new FakeWa());
}
$waRaw = '255700000001';
function wa_say(string $t) {
    global $waRaw;
    $req = Request::create('/api/webhooks/mosms/menu', 'POST', ['secret' => 'test-secret', 'mosms_tenant_id' => 987654321, 'phone' => $waRaw, 'text' => $t], [], [], ['HTTP_ACCEPT' => 'application/json']);
    app()->handle($req);
}
function wa_session(): ?WhatsappRenewalSession {
    global $tenant, $waRaw;
    $phone = \App\Helpers\PhoneHelper::normalize($waRaw);
    return WhatsappRenewalSession::withoutGlobalScopes()->where('tenant_id', $tenant->id)->where('phone', $phone)->first();
}
function wa_open(Client $c) {
    global $tenant, $waRaw;
    $phone = \App\Helpers\PhoneHelper::normalize($waRaw);
    WhatsappRenewalSession::updateOrCreate(['tenant_id' => $tenant->id, 'phone' => $phone],
        ['client_id' => $c->id, 'flow' => null, 'state' => null, 'items' => null, 'language' => 'en', 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(30)]);
    FakeWa::$sent = [];
    wa_say('3'); wa_say('2');
}
function wa_text(): string { return implode("\n---\n", array_column(FakeWa::$sent, 'text')); }

use App\Services\Hosting\PayLaterUpgradeService;
use Illuminate\Support\Carbon;

function up(Client $c, HostingAccount $a, ProductService $p, ?string $mode = null) {
    return portal('upgrade', $c, $a, ['product_service_id' => $p->id] + ($mode ? ['mode' => $mode] : []));
}
function marker(HostingAccount $a): ?array { return $a->fresh()->subscription->fresh()->metadata['pay_later_upgrade'] ?? null; }
function plog(HostingAccount $a, string $action): int {
    return ProvisioningLog::withoutGlobalScopes()->where('hosting_account_id', $a->id)->where('action', $action)->count();
}
function staffN() { global $tenant; return User::withPermission($tenant->id, 'hosting.change_package'); }
function neutral(string $t): bool { return !preg_match('/hetzner|name\.com|namecheap|linode|usd|\$/i', $t); }

scenario('eligible bandwidth-suspended: upgrade + restore BEFORE payment, invoice due +3d', function () {
    global $whmCalls;
    [$client, $acct] = mkAccount();
    $big = mkPlan('BW Big', 30000, 'pkg_big');
    [$c, $d] = up($client, $acct, $big);
    ok($c === 201 && $d['data']['pay_later'] === true && $d['data']['restored'] === true, 'pay-later applied and restored');
    ok(str_contains($d['message'], 'restored') && str_contains($d['message'], 'is due by'), 'message: restored + due date');
    ok(neutral($d['message']), 'neutral wording');
    $doc = Document::withoutGlobalScopes()->findOrFail($d['data']['document_id']);
    ok($doc->status === 'sent' && $doc->due_date->toDateString() === now()->addDays(3)->toDateString(), 'invoice sent, due today+3');
    ok(str_contains($doc->notes, 'pay within 3 days') && (float) $doc->total > 0, 'invoice note mentions pay within 3 days');
    ok(whmCount('changepackage') === 1 && whmCount('unsuspendacct') === 1 && whmCount('showbw') >= 1, 'changepackage + showbw + unsuspendacct now: ' . implode(',', $whmCalls));
    ok(empty(array_diff($whmCalls, ['listpkgs', 'changepackage', 'showbw', 'unsuspendacct'])), 'no other WHM calls');
    $acct = $acct->fresh();
    ok($acct->status === 'active' && $acct->package === 'pkg_big' && $acct->subscription->product_service_id === $big->id, 'account active on new package, subscription switched');
    $m = marker($acct);
    ok($m && $m['status'] === 'pending' && $m['document_id'] === $doc->id && $m['previous_cpanel_package'] === 'pkg_cur' && $m['due_date'] === $doc->due_date->toDateString(), 'pending marker with previous plan data');
    ok(empty($acct->subscription->metadata['pending_plan_change']), 'no pay-first pending change recorded');
    ok(plog($acct, 'pay_later_upgrade_applied') === 1, 'provisioning log pay_later_upgrade_applied');
    if (staffN()->isNotEmpty()) {
        ok(Notification::sent(staffN()->first(), \App\Notifications\HostingPayLaterUpgradeNotification::class)->filter(fn ($n) => $n->kind === 'applied')->count() === 1, 'staff notified: upgrade applied before payment');
    }
    // paying later does NOT re-apply
    $whmCalls = [];
    $doc->update(['status' => 'paid']);
    ok($whmCalls === [], 'paying makes no WHM call');
    ok(marker($acct) === null && plog($acct, 'pay_later_upgrade_paid') === 1, 'marker cleared + paid logged');
    ok($acct->fresh()->subscription->product_service_id === $big->id && $acct->fresh()->package === 'pkg_big', 'plan unchanged by payment');
    (new \App\Observers\DocumentObserver())->updated($doc->setAttribute('status', 'paid'));
    ok($whmCalls === [] && plog($acct, 'pay_later_upgrade_paid') === 1, 'replay idempotent');
    // second within 60 days: refused -> pay-first fallback
    $acct->update(['status' => 'suspended', 'meta' => array_merge($acct->fresh()->meta, ['bw_used_bytes' => 25 * GB, 'bw_limit_bytes' => 20 * GB])]);
    $huge = mkPlan('BW Huge', 90000, 'pkg_big2');
    $whmCalls = [];
    [$c, $d] = up($client, $acct, $huge);
    ok($c === 201 && $d['data']['pay_later'] === false && str_contains($d['data']['pay_later_reason'], '60 days'), 'second within 60 days -> pay-first with reason');
    ok(str_contains($d['message'], 'pay the invoice first') && whmCount('changepackage') === 0, 'told to pay first; nothing applied');
});

scenario('guards fall back to pay-first', function () {
    global $whmCalls;
    $fallback = function (string $why, callable $setup, string $needle) {
        global $whmCalls;
        [$client, $acct] = mkAccount('suspended', 'active', null, null, 'g' . uniqid() . '.example.test');
        $big = ProductService::where('name', 'BW Big')->first() ?? mkPlan('BW Big', 30000, 'pkg_big');
        $setup($client, $acct, $big);
        $whmCalls = [];
        [$c, $d] = up($client, $acct, $big);
        ok($c === 201 && $d['data']['pay_later'] === false && str_contains((string) $d['data']['pay_later_reason'], $needle), "$why: falls back with reason ($needle)");
        ok(whmCount('changepackage') === 0 && $acct->fresh()->status === 'suspended' && ($why === 'pending pay-later exists' ? (marker($acct)['document_id'] ?? null) === 'x' : marker($acct) === null), "$why: nothing applied");
        $sub = $acct->fresh()->subscription->fresh();
        ok(!empty($sub->metadata['pending_plan_change']), "$why: classic pay-first invoice recorded");
    };
    $fallback('other invoice overdue >7d', function ($client) {
        Document::withoutGlobalScopes()->create(['tenant_id' => $client->tenant_id, 'client_id' => $client->id, 'type' => 'invoice', 'document_number' => 'ODX-' . uniqid(), 'date' => now()->subDays(30)->toDateString(), 'due_date' => now()->subDays(10)->toDateString(), 'subtotal' => 100, 'tax_amount' => 0, 'total' => 100, 'status' => 'overdue']);
    }, 'overdue');
    $fallback('pending pay-later exists', function ($client, $acct) {
        $sub = $acct->subscription; $sub->update(['metadata' => ['pay_later_upgrade' => ['status' => 'pending', 'document_id' => 'x', 'due_date' => now()->toDateString()]]]);
    }, 'waiting for payment');
    $fallback('60-day limit', function ($client, $acct) {
        $sub = $acct->subscription; $sub->update(['metadata' => ['pay_later_last_applied_at' => now()->subDays(20)->toIso8601String()]]);
    }, '60 days');
    $fallback('amount cap', function () { config(['hosting.pay_later_upgrade_max' => 100]); }, 'limit');
    config(['hosting.pay_later_upgrade_max' => 500000]);
    // a 5-day-overdue invoice does NOT block; 61-day-old previous does not block
    [$client, $acct] = mkAccount('suspended', 'active', null, null, 'ok1.example.test');
    $big = ProductService::where('name', 'BW Big')->first();
    Document::withoutGlobalScopes()->create(['tenant_id' => $client->tenant_id, 'client_id' => $client->id, 'type' => 'invoice', 'document_number' => 'ODY-' . uniqid(), 'date' => now()->subDays(30)->toDateString(), 'due_date' => now()->subDays(5)->toDateString(), 'subtotal' => 100, 'tax_amount' => 0, 'total' => 100, 'status' => 'overdue']);
    $acct->subscription->update(['metadata' => ['pay_later_last_applied_at' => now()->subDays(61)->toIso8601String()]]);
    [$c, $d] = up($client, $acct, $big);
    ok($c === 201 && $d['data']['pay_later'] === true, 'invoice overdue only 5d and last upgrade 61d ago -> allowed');
    // usage still over the new plan's KNOWN limit -> refused outright (as before)
    [$client, $acct] = mkAccount('suspended', 'active', null, null, 'ok2.example.test');
    $mid = ProductService::where('name', 'BW Mid')->first() ?? mkPlan('BW Mid', 20000, 'pkg_mid');
    [$c, $d] = up($client, $acct, $mid);
    ok($c === 422 && str_contains($d['message'], 'still below your current usage'), 'known limit below usage refused');
    // unknown limit allowed
    [$client, $acct] = mkAccount('suspended', 'active', null, null, 'ok3.example.test');
    $unk = mkPlan('BW Unknown', 25000, 'pkg_unk');
    [$c, $d] = up($client, $acct, $unk);
    ok($c === 201 && $d['data']['pay_later'] === true, 'unknown limit allowed pay-later');
});

scenario('options expose pay_later eligibility/reason; explicit pay_first honoured; non-admin cannot', function () {
    global $whmCalls;
    [$client, $acct] = mkAccount();
    $big = mkPlan('BW Big', 30000, 'pkg_big');
    [$c, $d] = portal('upgradeOptions', $client, $acct);
    $pl = collect($d['data']['plans'])->firstWhere('name', 'BW Big')['pay_later'];
    ok($c === 200 && $pl['eligible'] === true && $pl['due_date'] === now()->addDays(3)->toDateString() && $pl['total'] > 0, 'options: eligible with total + due date');
    [$c, $d] = up($client, $acct, $big, 'pay_first');
    ok($c === 201 && $d['data']['pay_later'] === false && whmCount('changepackage') === 0, 'explicit pay_first: classic invoice, nothing applied');
    // non-admin
    $req = Request::create('/x', 'POST', ['product_service_id' => $big->id]);
    $u = portalUser($client, 'user'); $req->setUserResolver(fn () => $u);
    try { app(PortalHostingController::class)->upgrade($req, $acct->fresh()); ok(false, 'non-admin blocked'); }
    catch (\Symfony\Component\HttpKernel\Exception\HttpException $e) { ok($e->getStatusCode() === 403, 'non-admin upgrade 403'); }
    $req = Request::create('/x', 'GET'); $req->setUserResolver(fn () => $u);
    $d = app(PortalHostingController::class)->upgradeOptions($req, $acct->fresh())->getData(true);
    ok(collect($d['data']['plans'])->firstWhere('name', 'BW Big')['pay_later']['eligible'] === false, 'non-admin: pay_later not eligible in options');
});

scenario('active / billing / other suspended keep pay-first', function () {
    global $whmCalls;
    [$client, $acct] = mkAccount('active', 'active', 1 * GB, 4 * GB, 'a1.example.test');
    $big = mkPlan('BW Big', 30000, 'pkg_big');
    [$c, $d] = up($client, $acct, $big);
    ok($c === 201 && ($d['data']['pay_later'] ?? null) === false && whmCount('changepackage') === 0 && marker($acct) === null, 'active: pay-first, nothing applied');
    [$client2, $acct2] = mkAccount('suspended', 'suspended', (int) (1 * GB), 4 * GB, 'a2.example.test');
    [$c] = up($client2, $acct2, $big);
    ok($c === 422 && marker($acct2) === null && whmCount('changepackage') === 0, 'billing-suspended refused');
    [$client3, $acct3] = mkAccount('suspended', 'active', (int) (1 * GB), 4 * GB, 'a3.example.test');
    [$c] = up($client3, $acct3, $big);
    ok($c === 422 && marker($acct3) === null, 'other-suspended refused');
});

scenario('WHM changepackage failure: everything rolled back, falls back to pay-first', function () {
    global $whmCalls;
    $GLOBALS['failCp'] = true;
    [$client, $acct] = mkAccount();
    $big = mkPlan('BW Big', 30000, 'pkg_big');
    [$c, $d] = up($client, $acct, $big);
    $acct = $acct->fresh();
    ok($c === 201 && $d['data']['pay_later'] === false, 'falls back to pay-first');
    ok($acct->status === 'suspended' && $acct->package === 'pkg_cur' && marker($acct) === null, 'account untouched, no marker');
    ok(Document::withoutGlobalScopes()->where('client_id', $client->id)->count() === 1, 'only the pay-first invoice exists (pay-later invoice rolled back)');
    ok(plog($acct, 'pay_later_upgrade_applied') === 0, 'not logged as applied');
});

scenario('tenant isolation on pay-later upgrade', function () {
    [$client, $acct] = mkAccount();
    $big = mkPlan('BW Big', 30000, 'pkg_big');
    $other = Client::create(['tenant_id' => $client->tenant_id, 'name' => 'Other', 'phone' => '2557' . random_int(10000000, 99999999), 'email' => 'o@example.test', 'status' => 'active']);
    [$c] = up($other, $acct, $big);
    ok($c === 404 && marker($acct) === null && $acct->fresh()->status === 'suspended', 'other client: 404, nothing applied');
});

scenario('review command: reminders idempotent, dry-run, staff alert once, NO automatic revert', function () {
    global $whmCalls, $tenant;
    DB::table('tenants')->where('id', $tenant->id)->update(['is_active' => 1, 'is_self_hosted' => 1]); // rolled back with the scenario
    ok(Tenant::find($tenant->id)->hasAccess(), 'test tenant has access for the review run');
    [$client, $acct] = mkAccount();
    $big = mkPlan('BW Big', 30000, 'pkg_big');
    [$c, $d] = up($client, $acct, $big);
    $doc = Document::withoutGlobalScopes()->findOrFail($d['data']['document_id']);
    $svc = app(PayLaterUpgradeService::class);
    $sent = fn ($cls) => Notification::sent($client, $cls)->count();
    $whmCalls = [];
    $r = $svc->review(); ok($r['reminders'] === 0 && $r['staff_alerts'] === 0, 'before due date: nothing');
    Carbon::setTestNow(now()->addDays(3));
    $r = $svc->review(true);
    ok($r['reminders'] === 1 && $sent(\App\Notifications\InvoiceSentNotification::class) === 0, 'dry-run counts but sends nothing');
    $svc->review(); $svc->review();
    ok($sent(\App\Notifications\InvoiceSentNotification::class) === 1, 'due day: exactly one reminder despite repeated runs');
    Carbon::setTestNow(now()->addDay());
    $svc->review(); $svc->review();
    ok($sent(\App\Notifications\InvoiceOverdueReminderNotification::class) === 1, 'day +1: one reminder');
    Carbon::setTestNow(now()->addDay());
    $svc->review();
    ok($sent(\App\Notifications\InvoiceOverdueReminderNotification::class) === 2, 'day +2: one more reminder');
    ok(marker($acct)['staff_alerted_at'] === null, 'no staff alert yet');
    Carbon::setTestNow(now()->addDay()); // +3 days after due
    $r = $svc->review(true);
    ok($r['staff_alerts'] === 1, 'dry-run reports the staff alert');
    $svc->review(); $svc->review();
    if (staffN()->isNotEmpty()) {
        ok(Notification::sent(staffN()->first(), \App\Notifications\HostingPayLaterUpgradeNotification::class)->filter(fn ($n) => $n->kind === 'unpaid')->count() === 1, 'staff alerted exactly once');
    }
    ok($sent(\App\Notifications\InvoiceOverdueReminderNotification::class) === 2, 'no client reminders after the reminder window');
    $acct = $acct->fresh();
    ok($whmCalls === [] && $acct->status === 'active' && $acct->package === 'pkg_big' && $acct->subscription->product_service_id === $big->id, 'NOTHING reverted or re-suspended automatically');
    ok(!in_array($doc->fresh()->status, ['cancelled', 'paid'], true) && marker($acct) !== null, 'invoice + marker still open');
    Carbon::setTestNow();
});

scenario('staff revert: previous plan restored through the apply path, invoice cancelled, guards', function () {
    global $whmCalls, $whmState;
    [$client, $acct, $cur] = mkAccount();
    $acct->subscription->update(['recurring_amount' => 12345]);
    $big = mkPlan('BW Big', 30000, 'pkg_big');
    [$c, $d] = up($client, $acct, $big);
    $doc = Document::withoutGlobalScopes()->findOrFail($d['data']['document_id']);
    $sub = $acct->fresh()->subscription->fresh();
    $whmCalls = [];
    $res = app(\App\Http\Controllers\HostingServiceController::class)->revertPayLaterUpgrade($sub);
    ok($res->getStatusCode() === 200, 'revert accepted');
    $acct = $acct->fresh(); $sub = $sub->fresh();
    ok(whmCount('changepackage') === 1 && $whmState['pkg'] === 'pkg_cur' && $acct->package === 'pkg_cur', 'WHM package switched back');
    ok($sub->product_service_id === $cur->id && (float) $sub->recurring_amount === 12345.0, 'previous product + recurring amount restored');
    ok($doc->fresh()->status === 'cancelled' && marker($acct) === null, 'unpaid invoice cancelled, marker cleared');
    ok(\App\Models\ClientCredit::withoutGlobalScopes()->where('client_id', $client->id)->count() === 0, 'no downgrade credit issued');
    ok($acct->status === 'active' && whmCount('suspendacct') === 0, 'account state left alone (no re-suspend)');
    ok(plog($acct, 'pay_later_upgrade_reverted') === 1, 'reverted logged');
    $res = app(\App\Http\Controllers\HostingServiceController::class)->revertPayLaterUpgrade($sub);
    ok($res->getStatusCode() === 422, 'second revert refused (no pending upgrade)');
    // paid invoice cannot be reverted
    [$client2, $acct2] = mkAccount('suspended', 'active', null, null, 'rv2.example.test');
    [$c, $d] = up($client2, $acct2, ProductService::where('name', 'BW Big')->first());
    Document::withoutGlobalScopes()->where('id', $d['data']['document_id'])->update(['status' => 'partial']);
    $res = app(\App\Http\Controllers\HostingServiceController::class)->revertPayLaterUpgrade($acct2->fresh()->subscription->fresh());
    ok($res->getStatusCode() === 422 && marker($acct2) !== null, 'partly paid invoice: revert refused, marker kept');
});

scenario('WhatsApp: pay-later upgrade (bilingual, neutral) applies immediately', function () {
    wa_boot();
    [$client, $acct] = mkAccount('suspended', 'active', null, null, 'bwtest.example.test', '255700000001');
    $big = mkPlan('BW Big', 30000, 'pkg_big');
    wa_open($client);
    FakeWa::$sent = [];
    wa_say('1'); wa_say('1');
    $t = wa_text();
    ok(wa_session()->state['step'] === 'upgrade_confirm', 'confirm step');
    ok(str_contains($t, 'Upgrade now') && str_contains($t, 'restored immediately') && str_contains($t, 'is due by') , 'confirm: pay-later wording');
    ok(str_contains($t, '1)') && str_contains($t, '2)') && neutral($t), 'yes/no options, neutral');
    ok(whmCount('changepackage') === 0, 'nothing applied before confirming');
    FakeWa::$sent = [];
    wa_say('NDIYO');
    $doc = Document::withoutGlobalScopes()->where('client_id', $client->id)->where('type', 'invoice')->latest()->first();
    ok($doc && $doc->status === 'sent' && $doc->due_date->toDateString() === now()->addDays(3)->toDateString(), 'invoice due +3d');
    ok($acct->fresh()->status === 'active' && whmCount('changepackage') === 1 && whmCount('unsuspendacct') === 1, 'restored immediately over WhatsApp');
    ok(str_contains(wa_text(), 'restored') && neutral(wa_text()), 'success message neutral');
    ok(marker($acct)['document_id'] === $doc->id, 'marker set');
    $doc->update(['status' => 'paid']);
    ok(whmCount('changepackage') === 1 && marker($acct) === null, 'paying later does not re-apply');
});

echo $fail ? "FAILED $fail\n" : "ALL PASSED\n";
exit($fail ? 1 : 0);
