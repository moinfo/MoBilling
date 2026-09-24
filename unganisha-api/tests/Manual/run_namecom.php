<?php
// php tests/Manual/run_namecom.php  (live DB rolled back; Name.com fully faked, Http::preventStrayRequests - NO real calls)
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Exceptions\NameComApiException;
use App\Http\Controllers\{DomainController, NameComController};
use App\Http\Controllers\Portal\PortalDomainController;
use App\Http\Middleware\CheckPermission;
use App\Models\{Client, ClientUser, Domain, DomainLog, NameComAccount, NameComAuditLog, Tenant, User};
use App\Services\Registrar\{NameComDriver, NameComDomainService};
use Illuminate\Http\Request;
use Illuminate\Support\Facades\{DB, Http, Log};

const TOKEN = 'nc_SECRET_TOKEN_abcdefghijklmnopqrstuvwxyz1234';
NameComDriver::$sleepOnRateLimit = false;
NameComDriver::$paginatedGapMs = 0;
$fail = 0;
function ok($c, $m) { global $fail; if (!$c) { $fail++; echo "FAIL $m\n"; } else echo "PASS $m\n"; }
function fk($x) { Http::swap(new \Illuminate\Http\Client\Factory()); Http::preventStrayRequests(); Http::fake($x); }
function j($r) { return $r->getData(true); }
function posts() { return Http::recorded(fn ($r) => $r->method() === 'POST')->count(); }
function hits() { return Http::recorded()->count(); }
function req(Request $rq, $u) { $rq->setUserResolver(fn () => $u); app()->instance('request', $rq); auth()->setUser($u); return $rq; }
function trap(callable $f) {
    try { return $f(); }
    catch (\Symfony\Component\HttpKernel\Exception\HttpException $e) { return response()->json(['message' => $e->getMessage()], $e->getStatusCode()); }
    catch (\Illuminate\Validation\ValidationException $e) { return response()->json(['message' => $e->getMessage()], 422); }
}
function staff(User $s, string $ctl, string $m, array $d = [], ...$args) {
    $rq = req(Request::create('/x', 'POST', $d), $s);
    $takesReq = in_array($m, ['saveAccount', 'link', 'updateNameservers'], true);
    return trap(fn () => $takesReq ? app($ctl)->$m($rq, ...$args) : app($ctl)->$m(...$args));
}
function portal(ClientUser $u, string $m, Domain $dom, array $d = []) {
    $rq = req(Request::create('/x', 'PUT', $d), $u);
    return trap(fn () => app(PortalDomainController::class)->$m($rq, $dom));
}
function dom(string $name, array $extra = []) {
    return array_merge(['domainName' => $name, 'createDate' => '2020-01-05T10:00:00Z', 'expireDate' => '2031-03-04T10:00:00Z', 'locked' => true, 'autorenewEnabled' => false,
        'nameservers' => ['ns1.name.com', 'ns2.name.com']], $extra);
}

DB::beginTransaction();
try {
    $tenantA = Tenant::withoutGlobalScopes()->where('name', 'MoBilling Test Co')->firstOrFail();
    $tenantB = Tenant::withoutGlobalScopes()->where('id', '!=', $tenantA->id)->whereHas('users')->first() ?? Tenant::withoutGlobalScopes()->where('id', '!=', $tenantA->id)->firstOrFail();
    $staffA = User::withoutGlobalScopes()->where('tenant_id', $tenantA->id)->firstOrFail();
    auth()->setUser($staffA);

    $logged = [];
    Log::listen(function ($e) use (&$logged) { $logged[] = $e->message . json_encode($e->context); });

    // ---------- credentials ----------
    fk(['api.name.com/core/v1/domains*' => Http::response(['domains' => [], 'totalCount' => 0])]);
    $r = staff($staffA, NameComController::class, 'saveAccount', ['username' => 'owner', 'token' => TOKEN, 'is_sandbox' => false]);
    ok($r->getStatusCode() === 200, 'save credentials ok (verified via read)');
    ok(!str_contains(json_encode(j($r)), TOKEN), 'save response never contains token');
    ok(j($r)['data']['token_hint'] === '••••1234', 'masked hint returned');
    ok(posts() === 0 && hits() === 1, 'verify made exactly one GET and no POST');
    $auth = Http::recorded()->first()[0]->header('Authorization')[0] ?? '';
    ok($auth === 'Basic ' . base64_encode('owner:' . TOKEN), 'HTTP Basic auth username:token');
    $acct = NameComAccount::first();
    ok($acct && $acct->token === TOKEN && DB::table('namecom_accounts')->where('id', $acct->id)->value('token') !== TOKEN, 'token stored encrypted at rest');
    ok(!str_contains(json_encode($acct->toArray()), TOKEN) && !str_contains(json_encode($acct->toSafeArray()), TOKEN), 'model serialisation hides token');
    ok(!str_contains(json_encode(j(staff($staffA, NameComController::class, 'account'))), TOKEN), 'GET account hides token');
    ok(NameComAuditLog::where('action', 'account.create')->exists(), 'account.create audited');
    ok(!str_contains(json_encode(NameComAuditLog::all()->toArray()), TOKEN), 'audit rows contain no token');

    // rotate w/o token keeps old token; bad token rejected and not saved
    fk(['api.name.com/*' => Http::response(['message' => 'Unauthorized'], 401)]);
    $r = staff($staffA, NameComController::class, 'saveAccount', ['username' => 'owner', 'token' => 'bad_token_value_1234']);
    ok($r->getStatusCode() === 422 && NameComAccount::first()->token === TOKEN, 'rejected token (401) not saved, old kept');
    ok(!str_contains(json_encode(j($r)), 'bad_token_value_1234'), 'error does not echo token');
    fk(['api.name.com/*' => Http::response(['message' => 'Permission Denied', 'details' => 'Authentication Error - Account Has Two-Step Verification Enabled'], 403)]);
    $r = staff($staffA, NameComController::class, 'test');
    ok($r->getStatusCode() === 422 && str_contains(j($r)['message'], 'two-step'), '2FA 403 -> clear message');
    ok(NameComAccount::first()->status === 'invalid', 'test marks account invalid on 403');
    fk(['api.name.com/core/v1/domains*' => Http::response(['domains' => []])]);
    $r = staff($staffA, NameComController::class, 'saveAccount', ['username' => 'owner2', 'token' => TOKEN . 'x']);
    ok($r->getStatusCode() === 200 && NameComAccount::first()->status === 'active' && NameComAccount::first()->token === TOKEN . 'x' && NameComAccount::count() === 1, 'rotate works, single account per tenant');
    ok(NameComAuditLog::where('action', 'account.rotate_token')->exists(), 'rotate audited');
    $r = staff($staffA, NameComController::class, 'saveAccount', ['username' => 'owner2']);
    ok($r->getStatusCode() === 200 && NameComAccount::first()->token === TOKEN . 'x', 'update without token keeps stored token');
    fk(['api.name.com/*' => Http::response([], 200)]);
    ok(staff($staffA, NameComController::class, 'test')->getStatusCode() === 200 && posts() === 0, 'test connection = read only');

    // sandbox uses dev host and -test username
    fk(['api.dev.name.com/*' => Http::response(['domains' => []])]);
    staff($staffA, NameComController::class, 'saveAccount', ['username' => 'owner2', 'is_sandbox' => true]);
    $q = Http::recorded()->first()[0];
    ok(str_starts_with($q->url(), 'https://api.dev.name.com/') && $q->header('Authorization')[0] === 'Basic ' . base64_encode('owner2-test:' . TOKEN . 'x'), 'sandbox: dev host + -test username');
    fk(['api.name.com/core/v1/domains*' => Http::response(['domains' => []])]);
    staff($staffA, NameComController::class, 'saveAccount', ['username' => 'owner', 'token' => TOKEN, 'is_sandbox' => false]);

    // ---------- allow-list ----------
    $drv = new NameComDriver(NameComAccount::first());
    fk(['*' => Http::response([], 200)]);
    $refuse = function (string $m, string $p) {
        try { NameComDriver::assertAllowed($m, $p); return false; } catch (NameComApiException) { return true; }
    };
    foreach ([['DELETE', '/core/v1/domains/a.com'], ['PUT', '/core/v1/domains/a.com'], ['PATCH', '/core/v1/domains/a.com'],
        ['POST', '/core/v1/domains/a.com:renew'], ['POST', '/core/v1/domains/a.com:purchase'], ['POST', '/core/v1/domains/a.com:setContacts'],
        ['POST', '/core/v1/domains'], ['POST', '/core/v1/transfers'], ['GET', '/core/v1/domains/a.com:getAuthCode'], ['GET', '/core/v1/account'],
        ['GET', '/core/v1/domains/a.com/records'], ['POST', '/core/v1/domains/a.com/records'], ['GET', '/core/v1/domains/../x'], ['POST', '/core/v1/domains/a.com:setNameservers/x'],
        ['GET', '/v4/anything'], ['POST', '/core/v1/domains/a.com:setNameservers?x=1']] as [$m, $p]) {
        ok($refuse($m, $p), "refused $m $p");
    }
    ok(!$refuse('GET', '/core/v1/domains') && !$refuse('GET', '/core/v1/domains/a.com') && !$refuse('POST', '/core/v1/domains/a.com:setNameservers'), 'allowed: list, get, setNameservers');
    $m = new ReflectionMethod($drv, 'request'); $m->setAccessible(true);
    foreach ([['DELETE', '/core/v1/domains/a.com'], ['POST', '/core/v1/domains/a.com:renew']] as [$mm, $pp]) {
        try { $m->invoke($drv, $mm, $pp); ok(false, "wrapper $mm $pp"); } catch (NameComApiException) { ok(hits() === 0, "wrapper refuses $mm $pp with zero HTTP"); }
    }
    foreach (['register', 'renew', 'transferIn'] as $fn) {
        try { $fn === 'register' ? $drv->register('a.com') : ($fn === 'renew' ? $drv->renew('a.com') : $drv->transferIn('a.com', 'x')); ok(false, "$fn"); }
        catch (\App\Exceptions\RegistrarApiException) { ok(hits() === 0, "contract $fn unsupported, no HTTP"); }
    }

    // ---------- list + pagination + 429 ----------
    $clientA = Client::create(['name' => 'NC Client A TEST', 'phone' => '255700000301', 'email' => 'nca@example.test', 'status' => 'active']);
    $clientB = Client::create(['name' => 'NC Client B TEST', 'phone' => '255700000302', 'email' => 'ncb@example.test', 'status' => 'active']);
    $pre = Domain::create(['client_id' => $clientA->id, 'name' => 'existing-nc-test.com', 'status' => 'active', 'auto_renew' => false, 'expires_at' => '2027-01-01', 'meta' => ['unmanaged' => true, 'external_notes' => 'keep me']]);
    fk(['api.name.com/core/v1/domains*' => Http::sequence()
        ->push('', 429, ['Retry-After' => '1'])
        ->push(['domains' => [dom('existing-nc-test.com'), dom('new-nc-test.net')], 'nextPage' => 2, 'lastPage' => 3])
        ->push(['domains' => [dom('third-nc-test.org')], 'nextPage' => 3, 'lastPage' => 3])
        ->push(['domains' => [dom('fourth-nc-test.com')]])]);
    $r = staff($staffA, NameComController::class, 'domains');
    $rows = collect(j($r)['data'])->keyBy('name');
    ok($r->getStatusCode() === 200 && $rows->count() === 4, 'list follows nextPage across 3 pages (4 domains) after a 429 retry');
    ok(hits() === 4 && posts() === 0, '1 retry + 3 pages, all GET');
    ok($rows['existing-nc-test.com']['in_mobilling'] && $rows['existing-nc-test.com']['client_name'] === 'NC Client A TEST' && !$rows['existing-nc-test.com']['linked'] && !$rows['new-nc-test.net']['in_mobilling'], 'shows which already in MoBilling');
    fk(['api.name.com/*' => Http::response('', 429, ['Retry-After' => '1'])]);
    $r = staff($staffA, NameComController::class, 'domains');
    ok($r->getStatusCode() === 422 && hits() === 4 && str_contains(j($r)['message'], 'rate limit'), 'persistent 429: gives up after 3 retries with message');

    // ---------- link / upgrade ----------
    $domCount = Domain::count();
    fk(['api.name.com/core/v1/domains/existing-nc-test.com' => Http::response(dom('existing-nc-test.com'))]);
    $r = staff($staffA, NameComController::class, 'link', ['domain_name' => 'Existing-NC-Test.com', 'client_id' => $clientA->id]);
    $pre->refresh();
    ok($r->getStatusCode() === 200 && Domain::count() === $domCount && $pre->meta['namecom']['nameservers'] === ['ns1.name.com', 'ns2.name.com'], 'existing unmanaged domain upgraded in place (no duplicate)');
    ok($pre->expires_at->toDateString() === '2031-03-04' && $pre->status === 'active' && $pre->meta['unmanaged'] === true && $pre->meta['external_notes'] === 'keep me', 'expiry/status synced, other meta preserved');
    ok(posts() === 0, 'link is read-only at Name.com');
    ok($pre->meta['namecom']['original_nameservers'] === ['ns1.name.com', 'ns2.name.com'], 'original nameservers remembered at link');
    fk(['api.name.com/core/v1/domains/new-nc-test.net' => Http::response(dom('new-nc-test.net', ['expireDate' => '2020-01-01T00:00:00Z']))]);
    $r = staff($staffA, NameComController::class, 'link', ['domain_name' => 'new-nc-test.net', 'client_id' => $clientB->id]);
    $new = Domain::where('name', 'new-nc-test.net')->first();
    ok($r->getStatusCode() === 200 && $new && $new->client_id === $clientB->id && $new->status === 'expired' && $new->tenant_id === $tenantA->id && $new->auto_renew === false && $new->registrar_account_id === null, 'new domain created, expired status from date, tenant scoped, no FRED account');
    ok(DomainLog::where('domain_id', $new->id)->where('action', 'namecom_linked')->exists(), 'link logged');
    fk([]);
    $r = staff($staffA, NameComController::class, 'link', ['domain_name' => 'x-nc-test.com', 'client_id' => (string) \Illuminate\Support\Str::uuid()]);
    ok($r->getStatusCode() === 422 && hits() === 0, 'unknown client refused before any HTTP');
    $foreign = Client::withoutGlobalScopes()->where('tenant_id', '!=', $tenantA->id)->first();
    if ($foreign) {
        $r = staff($staffA, NameComController::class, 'link', ['domain_name' => 'x-nc-test.com', 'client_id' => $foreign->id]);
        ok($r->getStatusCode() === 422 && hits() === 0, 'other tenant client refused');
    }
    $fred = Domain::create(['client_id' => $clientA->id, 'name' => 'fred-nc-test.co.tz', 'status' => 'active', 'registrar_account_id' => DB::table('registrar_accounts')->value('id'), 'meta' => []]);
    fk(['api.name.com/*' => Http::response(dom('fred-nc-test.co.tz'))]);
    $r = staff($staffA, NameComController::class, 'link', ['domain_name' => 'fred-nc-test.co.tz', 'client_id' => $clientA->id]);
    ok($r->getStatusCode() === 422 && !isset($fred->fresh()->meta['namecom']), 'FRED-managed domain can never be linked');
    // domain owned by another tenant
    $otherDom = Domain::withoutGlobalScopes()->where('tenant_id', '!=', $tenantA->id)->whereNotIn('status', ['cancelled', 'transferred_out'])->first();
    if ($otherDom) {
        fk(['api.name.com/*' => Http::response(dom($otherDom->name))]);
        $r = staff($staffA, NameComController::class, 'link', ['domain_name' => $otherDom->name, 'client_id' => $clientA->id]);
        ok($r->getStatusCode() === 422 && !isset($otherDom->fresh()->meta['namecom']), 'domain of another tenant cannot be hijacked');
    }

    // ---------- refresh ----------
    fk(['api.name.com/core/v1/domains/existing-nc-test.com' => Http::response(dom('existing-nc-test.com', ['expireDate' => '2032-03-04T00:00:00Z', 'nameservers' => ['ns1.linode.com', 'ns2.linode.com']]))]);
    $r = staff($staffA, DomainController::class, 'sync', [], $pre);
    ok($r->getStatusCode() === 200 && $pre->fresh()->expires_at->toDateString() === '2032-03-04' && $pre->fresh()->meta['namecom']['nameservers'][0] === 'ns1.linode.com' && posts() === 0, 'staff sync (existing button) refreshes from Name.com, read-only');

    // ---------- nameserver read / update (staff) ----------
    fk(['api.name.com/core/v1/domains/existing-nc-test.com' => Http::response(dom('existing-nc-test.com', ['nameservers' => ['NS1.Name.com', 'ns2.name.com']]))]);
    $r = staff($staffA, DomainController::class, 'nameservers', [], $pre);
    ok(j($r)['data']['nameservers'] === ['ns1.name.com', 'ns2.name.com'] && j($r)['data']['provider'] === 'namecom', 'live nameservers read (normalised)');
    fk(['api.name.com/core/v1/domains/existing-nc-test.com' => Http::response(['message' => 'boom'], 500)]);
    $r = staff($staffA, DomainController::class, 'nameservers', [], $pre);
    ok($r->getStatusCode() === 422 && str_contains(j($r)['message'], 'Could not read'), 'graceful error when Name.com fails');

    $target = ['ns1.linode.com', 'ns2.linode.com', 'ns3.linode.com', 'ns4.linode.com', 'ns5.linode.com'];
    fk(['api.name.com/core/v1/domains/existing-nc-test.com:setNameservers' => Http::response(dom('existing-nc-test.com', ['nameservers' => $target])),
        'api.name.com/core/v1/domains/existing-nc-test.com' => Http::response(dom('existing-nc-test.com'))]);
    $r = staff($staffA, DomainController::class, 'updateNameservers', ['nameservers' => array_map('strtoupper', $target)], $pre);
    ok($r->getStatusCode() === 200 && j($r)['data']['nameservers'] === $target, 'staff update ok');
    ok(posts() === 1, 'exactly one POST');
    $p = Http::recorded(fn ($q) => $q->method() === 'POST')->first()[0];
    ok($p->url() === 'https://api.name.com/core/v1/domains/existing-nc-test.com:setNameservers' && $p->data() === ['nameservers' => $target], 'POST to :setNameservers with exact body');
    $al = NameComAuditLog::where('action', 'nameservers.set')->orderByDesc('created_at')->orderByDesc('id')->first();
    ok($al && $al->target === 'existing-nc-test.com' && $al->request['from'] === ['ns1.name.com', 'ns2.name.com'] && $al->request['to'] === $target && $al->user_id === $staffA->id && $al->response_status === 200, 'audit row: who/domain/old->new');
    ok(!str_contains(json_encode(NameComAuditLog::all()->toArray()), TOKEN), 'audit still has no secrets');
    $dl = DomainLog::where('domain_id', $pre->id)->where('action', 'namecom_nameservers_changed')->first();
    ok($dl && $dl->request['to'] === $target && $dl->request['by_user'] === $staffA->id, 'domain log written');
    ok($pre->fresh()->meta['namecom']['nameservers'] === $target, 'local cache updated');

    // unchanged -> no POST
    fk(['api.name.com/core/v1/domains/existing-nc-test.com' => Http::response(dom('existing-nc-test.com', ['nameservers' => $target]))]);
    $r = staff($staffA, DomainController::class, 'updateNameservers', ['nameservers' => array_reverse($target)], $pre);
    ok($r->getStatusCode() === 200 && posts() === 0 && str_contains(j($r)['message'], 'No changes'), 'same set -> no POST');

    // validation: nothing sent
    fk([]);
    foreach ([['only.one.com'], ['ns1.a.com', 'ns1.a.com'], ['ns1.a.com', '1.2.3.4'], ['ns1.a.com', 'bad host'], ['ns1.a.com', 'localhost'], ['ns1.a.com', '-x.com'],
        array_map(fn ($i) => "ns$i.a.com", range(1, 14)), []] as $i => $bad) {
        $r = staff($staffA, DomainController::class, 'updateNameservers', ['nameservers' => $bad], $pre);
        ok($r->getStatusCode() === 422 && hits() === 0, "validation case $i refused with no HTTP");
    }
    fk(['api.name.com/core/v1/domains/existing-nc-test.com:setNameservers' => Http::response(dom('x')), 'api.name.com/core/v1/domains/existing-nc-test.com' => Http::response(dom('existing-nc-test.com', ['nameservers' => $target]))]);
    $thirteen = array_map(fn ($i) => "ns$i.example.com", range(1, 13));
    ok(staff($staffA, DomainController::class, 'updateNameservers', ['nameservers' => $thirteen], $pre)->getStatusCode() === 200, '13 nameservers accepted');

    // Name.com rejects -> friendly error, failure audited, no domain log
    fk(['api.name.com/core/v1/domains/existing-nc-test.com:setNameservers' => Http::response(['message' => 'Invalid Argument', 'details' => 'nameserver not found'], 400),
        'api.name.com/core/v1/domains/existing-nc-test.com' => Http::response(dom('existing-nc-test.com', ['nameservers' => $thirteen]))]);
    $before = DomainLog::where('domain_id', $pre->id)->where('action', 'namecom_nameservers_changed')->count();
    $r = staff($staffA, DomainController::class, 'updateNameservers', ['nameservers' => ['ns1.zzz.com', 'ns2.zzz.com']], $pre);
    ok($r->getStatusCode() === 422 && DomainLog::where('domain_id', $pre->id)->where('action', 'namecom_nameservers_changed')->count() === $before, 'remote 400 -> 422, no success log');
    ok(NameComAuditLog::where('action', 'nameservers.set')->where('response_status', 400)->exists(), 'failed write audited');

    // ---------- rate limit: 5 successful changes / domain / day ----------
    $n = DomainLog::where('domain_id', $pre->id)->where('action', 'namecom_nameservers_changed')->where('status', 'success')->count();
    for ($i = $n; $i < 5; $i++) DomainLog::create(['tenant_id' => $tenantA->id, 'domain_id' => $pre->id, 'action' => 'namecom_nameservers_changed', 'request' => [], 'status' => 'success']);
    fk([]);
    $r = staff($staffA, DomainController::class, 'updateNameservers', ['nameservers' => ['ns1.new.com', 'ns2.new.com']], $pre);
    ok($r->getStatusCode() === 422 && str_contains(j($r)['message'], 'limited to 5') && hits() === 0, '6th change in 24h refused, no HTTP');
    DomainLog::where('domain_id', $pre->id)->where('action', 'namecom_nameservers_changed')->update(['created_at' => now()->subDays(2)]);
    fk(['api.name.com/core/v1/domains/existing-nc-test.com:setNameservers' => Http::response(dom('x')), 'api.name.com/core/v1/domains/existing-nc-test.com' => Http::response(dom('existing-nc-test.com'))]);
    ok(staff($staffA, DomainController::class, 'updateNameservers', ['nameservers' => ['ns1.new.com', 'ns2.new.com']], $pre)->getStatusCode() === 200, 'limit window expires after a day');

    // ---------- portal ----------
    $mkUser = fn ($c, $role, $email) => ClientUser::create(['client_id' => $c->id, 'tenant_id' => $tenantA->id, 'name' => 'U ' . $email, 'email' => $email, 'password' => 'x-Secret-123', 'role' => $role, 'is_active' => true]);
    $uA = $mkUser($clientA, 'admin', 'nc-ua@example.test'); $uAv = $mkUser($clientA, 'viewer', 'nc-uav@example.test'); $uB = $mkUser($clientB, 'admin', 'nc-ub@example.test');
    DomainLog::where('domain_id', $pre->id)->where('action', 'namecom_nameservers_changed')->delete();

    fk(['api.name.com/core/v1/domains/existing-nc-test.com' => Http::response(dom('existing-nc-test.com'))]);
    $r = portal($uA, 'nameservers', $pre);
    ok($r->getStatusCode() === 200 && j($r)['data']['nameservers'] === ['ns1.name.com', 'ns2.name.com'] && j($r)['data']['editable'] === true, 'portal reads live nameservers');
    fk([]);
    ok(portal($uB, 'nameservers', $pre)->getStatusCode() === 404 && hits() === 0, "other client GET -> 404, no HTTP");
    ok(portal($uB, 'updateNameservers', $pre, ['nameservers' => ['ns1.evil.com', 'ns2.evil.com']])->getStatusCode() === 404 && hits() === 0, 'other client PUT -> 404, no HTTP');
    ok(portal($uAv, 'updateNameservers', $pre, ['nameservers' => ['ns1.a.com', 'ns2.a.com']])->getStatusCode() === 403 && hits() === 0, 'portal viewer -> 403');
    $r = portal($uA, 'updateNameservers', $pre, ['nameservers' => ['ns1.a.com']]);
    ok($r->getStatusCode() === 422 && hits() === 0, 'portal validation (min 2) refused');

    fk(['api.name.com/core/v1/domains/existing-nc-test.com:setNameservers' => Http::response(dom('x')), 'api.name.com/core/v1/domains/existing-nc-test.com' => Http::response(dom('existing-nc-test.com'))]);
    $r = portal($uA, 'updateNameservers', $pre, ['nameservers' => $target]);
    ok($r->getStatusCode() === 200 && posts() === 1 && Http::recorded(fn ($q) => $q->method() === 'POST' && $q->data() === ['nameservers' => $target])->count() === 1, 'portal admin update: one POST, exact body');
    $al = NameComAuditLog::where('action', 'nameservers.set')->orderByDesc('created_at')->orderByDesc('id')->first();
    ok($al->request['by_portal_user'] === $uA->id && $al->user_id === $uA->id && $al->request['to'] === $target, 'portal change audited with portal user');
    ok(!str_contains(json_encode(j($r)), TOKEN) && !str_contains(json_encode(j($r)), 'namecom_account'), 'portal response leaks nothing');
    $r = portal($uA, 'show', $pre);
    $show = app(PortalDomainController::class)->show(req(Request::create('/x'), $uA), $pre);
    ok(j($show)['data']['nameserver_managed'] === true && !str_contains(json_encode(j($show)), TOKEN), 'portal show flags nameserver_managed, no secrets');
    // portal error is generic
    fk(['api.name.com/core/v1/domains/existing-nc-test.com:setNameservers' => Http::response(['message' => 'x', 'details' => 'SECRET-INTERNAL'], 400), 'api.name.com/core/v1/domains/existing-nc-test.com' => Http::response(dom('existing-nc-test.com'))]);
    $r = portal($uA, 'updateNameservers', $pre, ['nameservers' => ['ns1.q.com', 'ns2.q.com']]);
    ok($r->getStatusCode() === 422 && !str_contains(json_encode(j($r)), 'SECRET-INTERNAL'), 'portal error message is generic');
    // portal rate limit shared
    for ($i = 0; $i < 5; $i++) DomainLog::create(['tenant_id' => $tenantA->id, 'domain_id' => $pre->id, 'action' => 'namecom_nameservers_changed', 'request' => [], 'status' => 'success']);
    fk([]);
    $r = portal($uA, 'updateNameservers', $pre, ['nameservers' => ['ns1.r.com', 'ns2.r.com']]);
    ok($r->getStatusCode() === 422 && hits() === 0, 'portal rate limit enforced');
    // unlinked/unmanaged domain still uses old manual flow (untouched)
    $plain = Domain::create(['client_id' => $clientA->id, 'name' => 'plain-nc-test.com', 'status' => 'active', 'meta' => ['unmanaged' => true]]);
    fk([]);
    $r = portal($uA, 'updateNameservers', $plain, ['nameservers' => ['ns1.p.com', 'ns2.p.com']]);
    ok($r->getStatusCode() === 200 && hits() === 0 && isset($plain->fresh()->meta['pending_nameserver_request']), 'unlinked unmanaged domain: existing manual flow unchanged, no HTTP');

    // ---------- tenant isolation & permissions ----------
    $other = User::withoutGlobalScopes()->where('tenant_id', $tenantB->id)->first();
    if ($other) {
        auth()->setUser($other);
        ok(NameComAccount::first() === null, 'tenant B cannot see tenant A credentials');
        ok(Domain::where('name', 'existing-nc-test.com')->doesntExist(), 'tenant B cannot resolve tenant A domain (route binding 404)');
        ok(NameComAuditLog::count() === 0, 'tenant B cannot see tenant A audit rows');
    } else echo "SKIP no tenant B user\n";
    auth()->setUser($staffA);

    $hasAll = fn ($u, $p) => $u->hasAnyPermission([$p]);
    $noPerm = User::withoutGlobalScopes()->whereNotNull('tenant_id')->whereNotNull('role_id')->get()->first(fn ($u) => !$u->isSuperAdmin() && !$u->hasAnyPermission(['domains.settings']));
    if ($noPerm) {
        $rq = Request::create('/x'); $rq->setUserResolver(fn () => $noPerm);
        ok((new CheckPermission())->handle($rq, fn () => response('ok'), 'domains.settings')->getStatusCode() === 403, 'user without domains.settings gets 403 (credentials routes)');
    } else echo "SKIP no user without domains.settings\n";
    $adm = User::withoutGlobalScopes()->whereHas('role', fn ($q) => $q->where('name', 'admin'))->get()->first(fn ($u) => !$u->isSuperAdmin() && $u->hasAnyPermission(['domains.settings']));
    if ($adm) {
        $rq = Request::create('/x'); $rq->setUserResolver(fn () => $adm);
        ok((new CheckPermission())->handle($rq, fn () => response('ok'), 'domains.settings')->getStatusCode() === 200, 'admin role passes domains.settings');
    }
    foreach (['domains.settings', 'domains.create', 'domains.manage_dns', 'domains.read'] as $perm) {
        $pid = DB::table('permissions')->where('name', $perm)->value('id');
        ok($pid && DB::table('role_permissions')->where('permission_id', $pid)->exists() && DB::table('tenant_permissions')->where('permission_id', $pid)->exists() && DB::table('subscription_plan_permissions')->where('permission_id', $pid)->exists(), "reused permission $perm exists in all three layers");
    }
    $routes = collect(app('router')->getRoutes())->filter(fn ($r) => str_starts_with($r->uri(), 'api/namecom'));
    ok($routes->count() === 6 && $routes->every(fn ($r) => collect($r->gatherMiddleware())->contains(fn ($m) => str_starts_with($m, 'permission:domains.'))), 'all namecom routes are permission-gated');

    // ---------- secrets never logged ----------
    ok(!str_contains(implode("\n", $logged), TOKEN), 'token never appears in application logs');
} catch (\Throwable $e) {
    $fail++; echo "EXCEPTION: " . $e->getMessage() . "\n" . $e->getFile() . ':' . $e->getLine() . "\n";
} finally {
    DB::rollBack();
}
echo $fail ? "\n$fail FAILED\n" : "\nALL PASSED\n";
exit($fail ? 1 : 0);
