<?php
// php tests/Manual/run_hosting_bandwidth_upgrade.php
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
        $whmCalls = []; $whmState = ['pkg' => 'pkg_cur', 'used' => (int) (4.14 * GB)];
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

scenario('portal show + upgradeOptions for a bandwidth-suspended account', function () {
    [$client, $acct] = mkAccount();
    $big = mkPlan('BW Big', 30000, 'pkg_big'); $mid = mkPlan('BW Mid', 20000, 'pkg_mid');
    $unk = mkPlan('BW Unknown', 25000, 'pkg_unk'); $low = mkPlan('BW Low', 5000, 'pkg_low');
    [$c, $d] = portal('show', $client, $acct);
    ok($c === 200 && $d['data']['suspension_reason'] === 'bandwidth', 'show payload carries suspension_reason=bandwidth');
    [$c, $d] = portal('upgradeOptions', $client, $acct);
    ok($c === 200, 'options allowed for bandwidth-suspended');
    $plans = collect($d['data']['plans']);
    ok($plans->pluck('name')->sort()->values()->all() === ['BW Big', 'BW Mid', 'BW Unknown'], 'only upgrades offered (no downgrade, no current)');
    ok($plans->firstWhere('name', 'BW Big')['fixes_suspension'] === true, 'BW Big (20 GB) fixes suspension');
    ok($plans->firstWhere('name', 'BW Mid')['fixes_suspension'] === false, 'BW Mid (4 GB) does not fix (usage 4.14 GB)');
    ok($plans->firstWhere('name', 'BW Unknown')['fixes_suspension'] === null, 'unknown package limit -> null, not guessed');
    ok($plans->first()['name'] === 'BW Big' && $plans->last()['name'] === 'BW Mid', 'fixing plans sorted first, non-fixing last');
    ok($plans->every(fn ($p) => $p['due_now'] > 0), 'prorated charge present');
    ok(whmCount('changepackage') === 0 && whmCount('unsuspendacct') === 0, 'options made no mutating WHM call');
});

scenario('billing / other suspension and non-active refused', function () {
    [$client, $acct] = mkAccount('suspended', 'suspended', (int) (1 * GB), 4 * GB, 'billing.example.test');
    $big = mkPlan('BW Big', 30000, 'pkg_big');
    [$c, $d] = portal('upgradeOptions', $client, $acct);
    ok($c === 422 && $d['message'] === 'Please settle your unpaid invoices first.', 'billing: options refused with clear message');
    [$c, $d] = portal('upgrade', $client, $acct, ['product_service_id' => $big->id]);
    ok($c === 422 && $d['message'] === 'Please settle your unpaid invoices first.', 'billing: upgrade refused');
    [$client2, $acct2] = mkAccount('suspended', 'active', (int) (1 * GB), 4 * GB, 'other.example.test');
    $big2 = ProductService::where('name', 'BW Big')->first();
    [$c, $d] = portal('upgrade', $client2, $acct2, ['product_service_id' => $big2->id]);
    ok($c === 422 && $d['message'] === 'This account is suspended; please contact support.', 'other: upgrade refused with contact-support message');
    [$client3, $acct3] = mkAccount('failed', 'active', null, null, 'failed.example.test');
    [$c] = portal('upgradeOptions', $client3, $acct3);
    ok($c === 422, 'failed account refused');
    ok(Document::where('client_id', $client->id)->count() === 0 && Document::where('client_id', $client2->id)->count() === 0, 'no invoices created');
});

scenario('upgrade refusals: downgrade, non-fixing plan; active account unaffected', function () {
    [$client, $acct] = mkAccount();
    $low = mkPlan('BW Low', 5000, 'pkg_low'); $mid = mkPlan('BW Mid', 20000, 'pkg_mid');
    [$c, $d] = portal('upgrade', $client, $acct, ['product_service_id' => $low->id]);
    ok($c === 422 && str_contains($d['message'], 'higher plan'), 'downgrade refused for bandwidth-suspended');
    [$c, $d] = portal('upgrade', $client, $acct, ['product_service_id' => $mid->id]);
    ok($c === 422 && str_contains($d['message'], 'still below your current usage'), 'plan known to stay under usage refused');
    // active account keeps downgrade options
    [$client2, $acct2] = mkAccount('active', 'active', 1 * GB, 4 * GB, 'act.example.test');
    [$c, $d] = portal('upgradeOptions', $client2, $acct2);
    $names = collect($d['data']['plans'])->pluck('name')->all();
    ok($c === 200 && in_array('BW Low', $names) && collect($d['data']['plans'])->every(fn ($p) => $p['fixes_suspension'] === null), 'active account: all plans, no fixes flag');
});

scenario('invoice -> pay -> changepackage + unsuspend (full path), idempotent', function () use ($tenant) {
    global $whmCalls, $whmState;
    [$client, $acct] = mkAccount();
    $big = mkPlan('BW Big', 30000, 'pkg_big');
    [$c, $d] = portal('upgrade', $client, $acct, ['product_service_id' => $big->id]);
    ok($c === 201 && str_contains($d['message'], 'restored automatically'), 'invoice created for bandwidth-suspended, client told account is restored automatically');
    $doc = Document::withoutGlobalScopes()->findOrFail($d['data']['document_id']);
    ok((float) $doc->total > 0 && $doc->status === 'sent', 'prorated invoice');
    ok(whmCount('changepackage') === 0, 'nothing applied before payment');
    $whmCalls = [];
    $doc->update(['status' => 'paid']);
    $acct = $acct->fresh();
    ok(whmCount('changepackage') === 1 && whmCount('unsuspendacct') === 1, 'exactly one changepackage + one unsuspendacct after payment: ' . implode(',', $whmCalls));
    ok(array_search('changepackage', $whmCalls) < array_search('unsuspendacct', $whmCalls), 'changepackage happens before unsuspend');
    ok($acct->status === 'active' && $acct->package === 'pkg_big', 'account active on the new package');
    ok((int) $acct->meta['bw_limit_bytes'] === 20480 * 1048576, 'stored bw limit refreshed from WHM');
    ok($acct->subscription->product_service_id === $big->id, 'subscription switched');
    $logs = ProvisioningLog::withoutGlobalScopes()->where('hosting_account_id', $acct->id)->where('action', 'bandwidth_upgrade_reactivated')->get();
    ok($logs->count() === 1 && $logs->first()->status === 'success', 'one provisioning log entry');
    $staff = User::withPermission($tenant->id, 'hosting.change_package');
    if ($staff->isNotEmpty()) {
        ok(Notification::sent($staff->first(), \App\Notifications\HostingBandwidthUpgradeNotification::class)->filter(fn ($n) => $n->restored === true)->count() === 1, 'staff notified once (reactivated)');
    } else { echo "NOTE no staff with hosting.change_package in test tenant; notification assertion skipped\n"; }
    // idempotency
    $whmCalls = [];
    $doc->refresh();
    (new \App\Observers\DocumentObserver())->updated($doc->setAttribute('status', 'paid'));
    app(BandwidthSuspensionService::class)->afterPackageChange($acct->fresh());
    ok($whmCalls === [], 'replay makes no WHM call');
    ok(ProvisioningLog::withoutGlobalScopes()->where('hosting_account_id', $acct->id)->where('action', 'bandwidth_upgrade_reactivated')->count() === 1, 'replay does not log again');
});

scenario('usage still >= new limit -> stays suspended, staff notified once', function () use ($tenant) {
    global $whmCalls, $whmState;
    [$client, $acct] = mkAccount('suspended', 'active', (int) (6 * GB), 4 * GB);
    $whmState['used'] = 6 * GB;
    $unk = mkPlan('BW Unknown', 25000, 'pkg_unk'); // limit not knowable ahead of time; WHM reports 5000 MB after the change
    [$c, $d] = portal('upgrade', $client, $acct, ['product_service_id' => $unk->id]);
    ok($c === 201, 'unknown-limit plan is allowed (not guessed)');
    $doc = Document::withoutGlobalScopes()->findOrFail($d['data']['document_id']);
    $doc->update(['status' => 'paid']);
    $acct = $acct->fresh();
    ok(whmCount('changepackage') === 1 && whmCount('unsuspendacct') === 0, 'package changed but NOT unsuspended');
    ok($acct->status === 'suspended', 'still suspended');
    ok(ProvisioningLog::withoutGlobalScopes()->where('hosting_account_id', $acct->id)->where('action', 'bandwidth_upgrade_still_suspended')->count() === 1, 'logged as still suspended');
    $staff = User::withPermission($tenant->id, 'hosting.change_package');
    if ($staff->isNotEmpty()) {
        ok(Notification::sent($staff->first(), \App\Notifications\HostingBandwidthUpgradeNotification::class)->filter(fn ($n) => $n->restored === false)->count() === 1, 'staff notified once (still suspended)');
    }
    app(BandwidthSuspensionService::class)->afterPackageChange($acct->fresh());
    ok(ProvisioningLog::withoutGlobalScopes()->where('hosting_account_id', $acct->id)->where('action', 'bandwidth_upgrade_still_suspended')->count() === 1, 'replay does not re-log/re-notify');
    if ($staff->isNotEmpty()) { ok(Notification::sent($staff->first(), \App\Notifications\HostingBandwidthUpgradeNotification::class)->count() === 1, 'replay sends no second notification'); }
});

scenario('zero-charge apply path shares the same reactivation', function () {
    global $whmCalls;
    [$client, $acct] = mkAccount();
    $big = mkPlan('BW Big', 30000, 'pkg_big');
    app(PlanChangeService::class)->apply($acct->subscription->fresh(), $big);
    $acct = $acct->fresh();
    ok($acct->status === 'active' && whmCount('changepackage') === 1 && whmCount('unsuspendacct') === 1, 'apply() alone (no invoice) also reactivates');
});

scenario('non-bandwidth suspended account is never auto-unsuspended by a package change', function () {
    global $whmCalls;
    [$client, $acct] = mkAccount('suspended', 'suspended', (int) (1 * GB), 4 * GB, 'bill2.example.test');
    $big = mkPlan('BW Big', 30000, 'pkg_big');
    app(PlanChangeService::class)->apply($acct->subscription->fresh(), $big);
    ok($acct->fresh()->status === 'suspended' && whmCount('unsuspendacct') === 0, 'billing-suspended stays suspended');
});

scenario('tenant isolation: another client cannot see or upgrade the account', function () {
    [$client, $acct] = mkAccount();
    $big = mkPlan('BW Big', 30000, 'pkg_big');
    $other = Client::create(['tenant_id' => $client->tenant_id, 'name' => 'Other', 'phone' => '2557' . random_int(10000000, 99999999), 'email' => 'o@example.test', 'status' => 'active']);
    [$c] = portal('upgradeOptions', $other, $acct);
    ok($c === 404, 'options 404 for another client');
    [$c] = portal('upgrade', $other, $acct, ['product_service_id' => $big->id]);
    ok($c === 404, 'upgrade 404 for another client');
    [$c] = portal('show', $other, $acct);
    ok($c === 404, 'show 404 for another client');
});

scenario('staff endpoint: bandwidth-suspended subscription may be upgraded (status gate is on the subscription)', function () {
    global $staffUser;
    [$client, $acct] = mkAccount();
    $big = mkPlan('BW Big', 30000, 'pkg_big');
    $req = Request::create('/x', 'POST', ['product_service_id' => $big->id, 'mode' => 'invoice']);
    $req->setUserResolver(fn () => auth()->user());
    $res = app(\App\Http\Controllers\HostingServiceController::class)->upgrade($req, $acct->subscription->fresh());
    ok(in_array($res->getStatusCode(), [200, 201]), 'staff upgrade accepted for bandwidth-suspended account');
    $doc = Document::withoutGlobalScopes()->where('client_id', $client->id)->latest()->first();
    $doc->update(['status' => 'paid']);
    ok($acct->fresh()->status === 'active', 'staff-created invoice, once paid, also restores the account');
});

// ── WhatsApp matrix ──
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

scenario('WhatsApp: bandwidth-suspended account shows reason + upgrade, completes upgrade invoice', function () {
    wa_boot();
    [$client, $acct] = mkAccount('suspended', 'active', null, null, 'bwtest.example.test', '255700000001');
    $big = mkPlan('BW Big', 30000, 'pkg_big'); $mid = mkPlan('BW Mid', 20000, 'pkg_mid'); $low = mkPlan('BW Low', 5000, 'pkg_low');
    wa_open($client);
    $t = wa_text();
    ok(str_contains($t, 'Suspended: bandwidth limit reached'), 'account card explains bandwidth suspension');
    ok(wa_session()->state['options'] === ['upgrade', 'support'], 'menu offers upgrade + support only');
    ok(!preg_match('/hetzner|name\.com|linode|usd|\$/i', $t), 'neutral wording');
    FakeWa::$sent = [];
    wa_say('1');
    $t = wa_text();
    ok(wa_session()->state['step'] === 'upgrade_pick', 'upgrade list shown');
    ok(str_contains($t, 'BW Big') && str_contains($t, 'restores your hosting'), 'fixing plan listed and tagged');
    ok(!str_contains($t, 'BW Mid') && !str_contains($t, 'BW Low'), 'non-fixing and downgrade plans not listed');
    wa_say('1');
    ok(str_contains(wa_text(), 'restored automatically'), 'confirm message says the account is restored automatically');
    wa_say('NDIYO');
    $doc = Document::withoutGlobalScopes()->where('client_id', $client->id)->where('type', 'invoice')->latest()->first();
    ok($doc && (float) $doc->total > 0, 'upgrade invoice created over WhatsApp');
    $doc->update(['status' => 'paid']);
    ok($acct->fresh()->status === 'active' && whmCount('unsuspendacct') === 1, 'paying it restores the account');
});

foreach ([['suspended', 'suspended', 'billing'], ['suspended', 'active', 'other']] as [$st, $sub, $name])
scenario("WhatsApp: $name suspension gets no upgrade and cannot force it", function () use ($st, $sub, $name) {
    wa_boot();
    {
        [$client, $acct] = mkAccount($st, $sub, (int) (1 * GB), 4 * GB, "$name.example.test", '255700000001');
        $big = ProductService::where('name', 'BW Big')->first() ?? mkPlan('BW Big', 30000, 'pkg_big');
        wa_open($client);
        ok(!in_array('upgrade', wa_session()->state['options'], true), "$name: no upgrade option in menu");
        ok(!str_contains(wa_text(), 'bandwidth limit reached'), "$name: not blamed on bandwidth");
        // forge the confirm step
        WhatsappRenewalSession::withoutGlobalScopes()->where('phone', \App\Helpers\PhoneHelper::normalize('255700000001'))->update([
            'flow' => 'hosting_manage', 'state' => ['step' => 'upgrade_confirm', 'account_id' => $acct->id, 'plan_id' => $big->id, 'account_ids' => [$acct->id]]]);
        wa_say('NDIYO');
        ok(Document::withoutGlobalScopes()->where('client_id', $client->id)->count() === 0, "$name: forced confirm creates no invoice");
    }
});

echo $fail ? "FAILED $fail\n" : "ALL PASSED\n";
exit($fail ? 1 : 0);
