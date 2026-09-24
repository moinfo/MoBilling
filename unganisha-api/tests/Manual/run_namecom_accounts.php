<?php
// php tests/Manual/run_namecom_accounts.php  (live DB rolled back; Name.com fully faked, Http::preventStrayRequests - NO real calls)
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Exceptions\NameComApiException;
use App\Http\Controllers\{DomainController, NameComController, NameComSalesController};
use App\Http\Controllers\Portal\PortalDomainController;
use App\Models\{Client, ClientUser, Domain, DomainTld, NameComAccount, NameComAuditLog, Tenant, User};
use App\Services\Registrar\{NameComDriver, NameComDomainService};
use Illuminate\Http\Request;
use Illuminate\Support\Facades\{DB, Http, Log};

const TOK_A = 'nc_OWNER_TOKEN_aaaaaaaaaaaaaaaaaaaaaaaa1111';
const TOK_B = 'nc_SECOND_TOKEN_bbbbbbbbbbbbbbbbbbbbbbbb2222';
NameComDriver::$sleepOnRateLimit = false;
NameComDriver::$paginatedGapMs = 0;
$fail = 0;
function ok($c, $m) { global $fail; if (!$c) { $fail++; echo "FAIL $m\n"; } else echo "PASS $m\n"; }
function fk($x) { Http::swap(new \Illuminate\Http\Client\Factory()); Http::preventStrayRequests(); Http::fake($x); }
function j($r) { return $r->getData(true); }
function hits() { return Http::recorded()->count(); }
function posts() { return Http::recorded(fn ($r) => $r->method() === 'POST')->count(); }
function basic(string $u, string $t) { return 'Basic ' . base64_encode("$u:$t"); }
function users(): array { return Http::recorded()->map(fn ($p) => base64_decode(substr($p[0]->header('Authorization')[0] ?? '', 6)))->map(fn ($s) => explode(':', $s)[0])->unique()->values()->all(); }
function req(Request $rq, $u) { $rq->setUserResolver(fn () => $u); app()->instance('request', $rq); auth()->setUser($u); return $rq; }
function trap(callable $f) {
    try { return $f(); }
    catch (\Symfony\Component\HttpKernel\Exception\HttpException $e) { return response()->json(['message' => $e->getMessage()], $e->getStatusCode()); }
    catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) { return response()->json(['message' => 'not found'], 404); }
    catch (\Illuminate\Validation\ValidationException $e) { return response()->json(['message' => $e->getMessage()], 422); }
}
/** Call a NameComController method: $d = body, $q = query string. */
function nc($u, string $m, array $d = [], array $q = [], ...$args) {
    $rq = Request::create('/x', 'POST', $d); $rq->query->replace($q); req($rq, $u);
    $noReq = ['accountList', 'accountOptions', 'testAccount', 'test', 'account'];
    return trap(fn () => in_array($m, $noReq, true) ? app(NameComController::class)->$m(...$args) : app(NameComController::class)->$m($rq, ...$args));
}
function dom(string $name, array $extra = []) {
    return array_merge(['domainName' => $name, 'createDate' => '2020-01-05T10:00:00Z', 'expireDate' => '2031-03-04T10:00:00Z', 'locked' => true, 'autorenewEnabled' => false,
        'nameservers' => ['ns1.name.com', 'ns2.name.com']], $extra);
}
/** Fake where each Basic-auth username sees its own portfolio; $own = ['username' => ['a.com', ...]]. */
function fakeByUser(array $own, array $fail = []) {
    return ['api.name.com/*' => function ($r) use ($own, $fail) {
        $u = explode(':', base64_decode(substr($r->header('Authorization')[0] ?? '', 6)))[0];
        if (in_array($u, $fail, true)) return Http::response(['message' => 'Unauthorized'], 401);
        $path = parse_url($r->url(), PHP_URL_PATH);
        if ($path === '/core/v1/domains' && $r->method() === 'GET') return Http::response(['domains' => array_map(fn ($n) => dom($n), $own[$u] ?? []), 'totalCount' => count($own[$u] ?? [])]);
        if (preg_match('#^/core/v1/domains/([a-z0-9.-]+)(:setNameservers)?$#', $path, $m)) {
            if (!in_array($m[1], $own[$u] ?? [], true)) return Http::response(['message' => 'Not Found'], 404);
            return Http::response(dom($m[1], !empty($m[2]) ? ['nameservers' => $r['nameservers']] : []));
        }
        return Http::response([], 200);
    }];
}

DB::beginTransaction();
try {
    $tenantA = Tenant::withoutGlobalScopes()->where('name', 'MoBilling Test Co')->firstOrFail();
    $tenantB = Tenant::withoutGlobalScopes()->where('id', '!=', $tenantA->id)->whereHas('users')->first() ?? Tenant::withoutGlobalScopes()->where('id', '!=', $tenantA->id)->firstOrFail();
    $staffA = User::withoutGlobalScopes()->where('tenant_id', $tenantA->id)->firstOrFail();
    auth()->setUser($staffA);
    NameComAccount::withoutGlobalScopes()->where('tenant_id', $tenantA->id)->delete(); // clean slate (rolled back)

    $logged = [];
    Log::listen(function ($e) use (&$logged) { $logged[] = $e->message . json_encode($e->context); });

    // ---------- multi-account CRUD ----------
    fk(fakeByUser(['owner' => [], 'second' => []]));
    $r = nc($staffA, 'storeAccount', ['label' => 'Owner account', 'username' => 'owner', 'token' => TOK_A]);
    ok($r->getStatusCode() === 200 && j($r)['data']['is_default'] === true && j($r)['data']['label'] === 'Owner account', 'first account becomes the default');
    ok(hits() === 1 && posts() === 0 && Http::recorded()->first()[0]->header('Authorization')[0] === basic('owner', TOK_A), 'verify: one GET with the owner credentials');
    $idA = j($r)['data']['id'];
    fk(fakeByUser(['owner' => [], 'second' => []]));
    $r = nc($staffA, 'storeAccount', ['label' => 'Second user', 'username' => 'second', 'token' => TOK_B, 'is_sandbox' => false]);
    $idB = j($r)['data']['id'];
    ok($r->getStatusCode() === 200 && j($r)['data']['is_default'] === false && NameComAccount::count() === 2, 'second account added, not default');
    ok(users() === ['second'] && Http::recorded()->first()[0]->header('Authorization')[0] === basic('second', TOK_B), 'second account verified with ITS OWN credentials');
    $all = json_encode([j(nc($staffA, 'accountList')), j($r), j(nc($staffA, 'accountOptions'))], JSON_UNESCAPED_UNICODE);
    ok(!str_contains($all, TOK_A) && !str_contains($all, TOK_B) && str_contains($all, '••••2222') && str_contains($all, '"linked_domains"'), 'list/create/options never contain tokens; masked hints only');
    ok(!str_contains(json_encode(j(nc($staffA, 'accountOptions'))), 'token'), 'account options expose no token fields');
    ok(DB::table('namecom_accounts')->where('id', $idB)->value('token') !== TOK_B && NameComAccount::find($idB)->token === TOK_B, 'tokens encrypted at rest');
    ok(NameComAuditLog::where('action', 'account.create')->where('account_label', 'Second user')->exists() && NameComAuditLog::where('action', 'account.create')->where('account_label', 'Owner account')->exists(), 'audit rows record the account label');
    ok(!str_contains(json_encode(NameComAuditLog::all()->toArray()), TOK_A) && !str_contains(json_encode(NameComAuditLog::all()->toArray()), TOK_B), 'audit rows contain no token');

    ok(nc($staffA, 'storeAccount', ['label' => 'owner account', 'username' => 'third', 'token' => TOK_B . 'x'])->getStatusCode() === 422, 'duplicate label refused');
    ok(nc($staffA, 'storeAccount', ['label' => 'Another', 'username' => 'SECOND', 'token' => TOK_B . 'x'])->getStatusCode() === 422, 'duplicate username refused');
    ok(nc($staffA, 'storeAccount', ['label' => 'No token', 'username' => 'nt'])->getStatusCode() === 422, 'token required on create');
    fk(fakeByUser([], ['bad']));
    $n = NameComAccount::count();
    $r = nc($staffA, 'storeAccount', ['label' => 'Bad', 'username' => 'bad', 'token' => 'bad_token_value_1234']);
    ok($r->getStatusCode() === 422 && NameComAccount::count() === $n && !str_contains(json_encode(j($r)), 'bad_token_value_1234'), 'rejected credentials (401) are not stored and not echoed');

    // rotate B, per-account test
    fk(fakeByUser(['second' => []]));
    $r = nc($staffA, 'updateAccount', ['token' => TOK_B . 'R'], [], $idB);
    ok($r->getStatusCode() === 200 && j($r)['data']['token_hint'] === '••••222R', 'rotate returns the new masked hint');
    ok(NameComAccount::find($idB)->token === TOK_B . 'R' && NameComAccount::find($idA)->token === TOK_A, 'rotate touched only account B');
    ok(Http::recorded()->first()[0]->header('Authorization')[0] === basic('second', TOK_B . 'R') && NameComAuditLog::where('action', 'account.rotate_token')->where('account_label', 'Second user')->exists(), 'rotation verified with the new token and audited with label');
    $r = nc($staffA, 'updateAccount', ['label' => 'Second user (staff)'], [], $idB);
    ok($r->getStatusCode() === 200 && NameComAccount::find($idB)->token === TOK_B . 'R', 'rename keeps the stored token');
    fk(fakeByUser(['owner' => [], 'second' => []], ['second']));
    $r = nc($staffA, 'testAccount', [], [], $idB);
    ok($r->getStatusCode() === 422 && NameComAccount::find($idB)->status === 'invalid' && NameComAccount::find($idA)->status === 'active' && users() === ['second'], 'test of B uses B credentials and marks only B invalid');
    fk(fakeByUser(['owner' => [], 'second' => []]));
    ok(nc($staffA, 'testAccount', [], [], $idB)->getStatusCode() === 200 && NameComAccount::find($idB)->status === 'active' && posts() === 0, 'test re-validates B (read only)');

    // default switching
    $r = nc($staffA, 'updateAccount', ['is_default' => true], [], $idB);
    ok(NameComAccount::where('is_default', true)->count() === 1 && NameComAccount::find($idB)->is_default, 'exactly one default; switched to B');
    nc($staffA, 'updateAccount', ['is_default' => true], [], $idA);
    ok(NameComAccount::find($idA)->is_default && !NameComAccount::find($idB)->is_default, 'switched back to A');

    // ---------- import per account / all ----------
    $own = ['owner' => ['cahc-acc-test.com', 'trag-acc-test.com'], 'second' => ['nassh-acc-test.com', 'uzzar-acc-test.com']];
    fk(fakeByUser($own));
    $r = nc($staffA, 'domains', [], ['account_id' => $idA]);
    ok(collect(j($r)['data'])->pluck('name')->all() === ['cahc-acc-test.com', 'trag-acc-test.com'] && users() === ['owner'], 'import from account A: only its domains, only A credentials');
    fk(fakeByUser($own));
    $r = nc($staffA, 'domains', [], ['account_id' => $idB]);
    ok(collect(j($r)['data'])->pluck('name')->all() === ['nassh-acc-test.com', 'uzzar-acc-test.com'] && users() === ['second'] && j($r)['data'][0]['account_label'] === 'Second user (staff)', 'import from account B: the sub-user domains, only B credentials');
    fk(fakeByUser($own));
    $r = nc($staffA, 'domains', [], ['account_id' => 'all']);
    $rows = collect(j($r)['data']);
    ok($rows->pluck('name')->all() === ['cahc-acc-test.com', 'nassh-acc-test.com', 'trag-acc-test.com', 'uzzar-acc-test.com'] && $rows->firstWhere('name', 'nassh-acc-test.com')['account_id'] === $idB && $rows->firstWhere('name', 'cahc-acc-test.com')['account_label'] === 'Owner account' && posts() === 0, 'import ALL: aggregated, Account column data, GET only');
    ok(collect(users())->sort()->values()->all() === ['owner', 'second'], 'import ALL used each account own credentials');
    fk(fakeByUser($own, ['second']));
    $r = nc($staffA, 'domains', [], []);
    ok($r->getStatusCode() === 200 && count(j($r)['data']) === 2 && count(j($r)['errors']) === 1 && j($r)['errors'][0]['account_label'] === 'Second user (staff)', 'one failing account is reported without hiding the others');
    fk(fakeByUser($own, ['second', 'owner']));
    ok(nc($staffA, 'domains', [], ['account_id' => 'all'])->getStatusCode() === 422, 'all accounts failing -> 422');

    // ---------- link records account; nameservers use the domain account ----------
    $clientA = Client::create(['name' => 'NC Acc Client A TEST', 'phone' => '255700000401', 'email' => 'ncacc-a@example.test', 'status' => 'active']);
    $clientB = Client::create(['name' => 'NC Acc Client B TEST', 'phone' => '255700000402', 'email' => 'ncacc-b@example.test', 'status' => 'active']);
    fk(fakeByUser($own));
    $r = nc($staffA, 'link', ['domain_name' => 'nassh-acc-test.com', 'client_id' => $clientA->id, 'account_id' => $idB]);
    if ($r->getStatusCode() !== 200) echo json_encode(j($r)) . "\n";
    $dB = Domain::where('name', 'nassh-acc-test.com')->first();
    ok($r->getStatusCode() === 200 && $dB->meta['namecom']['account_id'] === $idB && users() === ['second'], 'link with account B records meta.namecom.account_id and reads via B');
    $lg = \App\Models\DomainLog::where('domain_id', $dB->id)->where('action', 'namecom_linked')->first();
    ok(($lg->request['account'] ?? null) === 'Second user (staff)', 'link log names the account');
    fk(fakeByUser($own));
    $r = nc($staffA, 'link', ['domain_name' => 'cahc-acc-test.com', 'client_id' => $clientA->id]);
    $dA = Domain::where('name', 'cahc-acc-test.com')->first();
    ok($r->getStatusCode() === 200 && $dA->meta['namecom']['account_id'] === $idA && users() === ['owner'], 'link without account uses the default account and records it');
    fk(fakeByUser($own));
    ok(nc($staffA, 'link', ['domain_name' => 'cahc-acc-test.com', 'client_id' => $clientA->id, 'account_id' => $idB])->getStatusCode() === 422, 'linking a domain the chosen account does not own fails (404 from Name.com), nothing written');
    ok(nc($staffA, 'link', ['domain_name' => 'x.com', 'client_id' => $clientA->id, 'account_id' => '00000000-0000-4000-8000-000000000000'])->getStatusCode() === 422, 'unknown account id refused');

    $target = ['ns1.linode.com', 'ns2.linode.com'];
    fk(fakeByUser($own));
    $rq = req(Request::create('/x', 'PUT', ['nameservers' => $target]), $staffA);
    $r = trap(fn () => app(DomainController::class)->updateNameservers($rq, $dB));
    ok($r->getStatusCode() === 200 && users() === ['second'] && Http::recorded(fn ($q) => $q->method() === 'POST' && str_ends_with($q->url(), '/nassh-acc-test.com:setNameservers') && $q->data() === ['nameservers' => $target])->count() === 1, 'nameserver update for B-domain: GET + one POST, all with B credentials');
    $al = NameComAuditLog::where('action', 'nameservers.set')->orderByDesc('created_at')->orderByDesc('id')->first();
    ok($al->namecom_account_id === $idB && $al->account_label === 'Second user (staff)', 'nameserver audit records the account');
    $rq = req(Request::create('/x', 'PUT', ['nameservers' => $target]), $staffA);
    fk(fakeByUser($own));
    $r = trap(fn () => app(DomainController::class)->updateNameservers($rq, $dA));
    ok($r->getStatusCode() === 200 && users() === ['owner'], 'A-domain update uses owner credentials');

    // legacy link (no account_id) -> default; deleted account -> default
    $leg = Domain::create(['client_id' => $clientA->id, 'name' => 'trag-acc-test.com', 'status' => 'active', 'meta' => ['unmanaged' => true, 'namecom' => ['nameservers' => ['ns1.name.com', 'ns2.name.com'], 'original_nameservers' => ['ns1.name.com']]]]);
    fk(fakeByUser($own));
    $ns = app(NameComDomainService::class)->nameservers($leg);
    ok($ns === ['ns1.name.com', 'ns2.name.com'] && users() === ['owner'], 'legacy link without account_id falls back to the default account');
    $ghost = Domain::create(['client_id' => $clientA->id, 'name' => 'ghost-acc-test.com', 'status' => 'active', 'meta' => ['unmanaged' => true, 'namecom' => ['account_id' => '00000000-0000-4000-8000-000000000001', 'nameservers' => []]]]);
    fk(['api.name.com/*' => Http::response(dom('ghost-acc-test.com'))]);
    app(NameComDomainService::class)->nameservers($ghost);
    ok(Http::recorded()->first()[0]->header('Authorization')[0] === basic('owner', TOK_A), 'account removed/unknown -> default account credentials');

    // sync keeps account_id
    fk(fakeByUser($own));
    app(NameComDomainService::class)->sync($dB);
    ok($dB->fresh()->meta['namecom']['account_id'] === $idB && users() === ['second'], 'refresh uses and keeps the domain account');

    // ---------- bulk link matched ----------
    $m1 = Domain::create(['client_id' => $clientB->id, 'name' => 'match1-acc-test.com', 'status' => 'active', 'meta' => ['unmanaged' => true]]);
    $m2 = Domain::create(['client_id' => $clientA->id, 'name' => 'match2-acc-test.com', 'status' => 'active', 'meta' => ['unmanaged' => true]]);
    $fred = Domain::create(['client_id' => $clientA->id, 'name' => 'fred-acc-test.co.tz', 'status' => 'active', 'registrar_account_id' => DB::table('registrar_accounts')->value('id'), 'meta' => []]);
    $own2 = ['owner' => ['match1-acc-test.com', 'brandnew-acc-test.com'], 'second' => ['match2-acc-test.com', 'fred-acc-test.co.tz', 'gone-acc-test.com']];
    fk(fakeByUser($own2));
    $r = nc($staffA, 'domains', [], ['account_id' => 'all']);
    $rows = collect(j($r)['data']);
    ok($rows->firstWhere('name', 'match1-acc-test.com')['in_mobilling'] === true && $rows->firstWhere('name', 'match1-acc-test.com')['linked'] === false && $rows->firstWhere('name', 'match1-acc-test.com')['client_name'] === 'NC Acc Client B TEST' && $rows->firstWhere('name', 'brandnew-acc-test.com')['in_mobilling'] === false, 'import list marks in-MoBilling-not-linked (with client) vs new');
    $items = [['domain_name' => 'match1-acc-test.com', 'account_id' => $idA], ['domain_name' => 'match2-acc-test.com', 'account_id' => $idB],
        ['domain_name' => 'brandnew-acc-test.com', 'account_id' => $idA], ['domain_name' => 'fred-acc-test.co.tz', 'account_id' => $idB], ['domain_name' => 'gone-acc-test.com', 'account_id' => $idB]];
    fk(fakeByUser($own2));
    $r = nc($staffA, 'linkMatched', ['items' => $items]);
    $st = collect(j($r)['data'])->pluck('status', 'name');
    ok($st['match1-acc-test.com'] === 'ready' && $st['match2-acc-test.com'] === 'ready' && $st['brandnew-acc-test.com'] === 'new' && $st['fred-acc-test.co.tz'] === 'skipped' && $st['gone-acc-test.com'] === 'new', 'preview: ready / new / skipped classification');
    ok(hits() === 0 && !isset($m1->fresh()->meta['namecom']) && !isset($m2->fresh()->meta['namecom']), 'preview makes no Name.com call and changes nothing');
    ok(nc($staffA, 'linkMatched', ['items' => $items, 'confirm' => false])->getStatusCode() === 200 && !isset($m1->fresh()->meta['namecom']), 'confirm=false still changes nothing');
    fk(fakeByUser($own2));
    $items2 = $items; $items2[0]['client_id'] = $clientA->id; // a browser-supplied client must be ignored
    $r = nc($staffA, 'linkMatched', ['items' => $items2, 'confirm' => true]);
    $st = collect(j($r)['data'])->pluck('status', 'name');
    ok($st['match1-acc-test.com'] === 'linked' && $st['match2-acc-test.com'] === 'linked' && $st['brandnew-acc-test.com'] === 'new' && $st['fred-acc-test.co.tz'] === 'skipped', 'confirm links only the matched rows');
    ok($m1->fresh()->client_id === $clientB->id && $m1->fresh()->meta['namecom']['account_id'] === $idA && $m2->fresh()->meta['namecom']['account_id'] === $idB && $m2->fresh()->client_id === $clientA->id, 'each keeps the MoBilling client and records its account');
    ok(!isset($fred->fresh()->meta['namecom']) && Domain::where('name', 'brandnew-acc-test.com')->doesntExist(), 'fred-managed and unmatched domains untouched (no rows created)');
    ok(posts() === 0 && collect(users())->sort()->values()->all() === ['owner', 'second'], 'bulk link is GET-only, each with the account credentials');
    fk(fakeByUser($own2));
    $r = nc($staffA, 'linkMatched', ['items' => [['domain_name' => 'match1-acc-test.com', 'account_id' => $idA]], 'confirm' => true]);
    ok(collect(j($r)['data'])[0]['status'] === 'skipped', 'already linked -> skipped (idempotent)');
    $m3 = Domain::create(['client_id' => $clientA->id, 'name' => 'wrongacct-acc-test.com', 'status' => 'active', 'meta' => ['unmanaged' => true]]);
    fk(fakeByUser($own2));
    $r = nc($staffA, 'linkMatched', ['items' => [['domain_name' => 'wrongacct-acc-test.com', 'account_id' => $idA]], 'confirm' => true]);
    ok(collect(j($r)['data'])[0]['status'] === 'failed' && !isset($m3->fresh()->meta['namecom']), 'domain not in the chosen account -> failed, not linked');
    ok(nc($staffA, 'linkMatched', ['items' => []])->getStatusCode() === 422, 'empty bulk refused');

    // ---------- registration: staff picks the account ----------
    DomainTld::create(['tenant_id' => $tenantA->id, 'tld' => 'nctesta', 'registrar' => 'namecom', 'register_price' => 90000, 'renew_price' => 90000, 'transfer_price' => 0, 'usd_register' => 21.98, 'usd_renew' => 21.98, 'is_active' => true]);
    $full = ['first_name' => 'Asha', 'last_name' => 'Mushi', 'address_1' => 'Plot 5', 'city' => 'Dar', 'state' => 'Dar', 'postcode' => '11101', 'country' => 'TZ'];
    $cr = Client::create(['name' => 'NC Acc Reg TEST', 'phone' => '255700000403', 'email' => 'ncacc-r@example.test', 'status' => 'active'] + $full);
    $q = Domain::create(['client_id' => $cr->id, 'name' => 'reg-acc-test.nctesta', 'status' => 'pending', 'meta' => ['unmanaged' => true, 'registrar' => 'namecom', 'awaiting_manual_registration' => true, 'namecom_years' => 1]]);
    $regFake = fn () => ['api.name.com/*' => function ($r) {
        $path = parse_url($r->url(), PHP_URL_PATH);
        if ($path === '/core/v1/domains:checkAvailability') return Http::response(['results' => [['domainName' => 'reg-acc-test.nctesta', 'purchasable' => true, 'premium' => false, 'purchaseType' => 'registration']]]);
        if ($path === '/core/v1/tldpricing') return Http::response(['pricing' => [['tld' => 'nctesta', 'duration' => 1, 'registrationPrice' => 21.98]]]);
        if ($path === '/core/v1/domains' && $r->method() === 'POST') return Http::response(['domain' => dom('reg-acc-test.nctesta'), 'order' => 1, 'totalPaid' => 21.98]);
        return Http::response(['message' => 'Not Found'], 404);
    }];
    $sales = function ($m, $d, $qr, $dm) use ($staffA) {
        $rq = Request::create('/x', 'POST', $d); $rq->query->replace($qr); req($rq, $staffA);
        return trap(fn () => app(NameComSalesController::class)->$m($rq, $dm));
    };
    fk($regFake());
    $pv = j($sales('registrationPreview', [], [], $q))['data'];
    ok($pv['account']['id'] === $idA && $pv['account']['label'] === 'Owner account' && users() === ['owner'] && count($pv['accounts']) === 2 && !str_contains(json_encode($pv), TOK_A), 'preview defaults to the default account and labels it; picker list has no tokens');
    fk($regFake());
    $pv = j($sales('registrationPreview', [], ['account_id' => $idB], $q))['data'];
    ok($pv['account']['id'] === $idB && users() === ['second'] && $pv['can_register'], 'preview with account B checks availability/price with B credentials');
    fk($regFake());
    $r = $sales('register', ['confirm' => true, 'usd_cost' => 21.98, 'account_id' => $idB], [], $q);
    $created = Http::recorded(fn ($x) => $x->method() === 'POST' && $x->url() === 'https://api.name.com/core/v1/domains')->count();
    ok($r->getStatusCode() === 200 && $created === 1 && users() === ['second'], 'registration charged to account B: one create POST, all with B credentials');
    ok($q->fresh()->meta['namecom']['account_id'] === $idB && NameComAuditLog::where('action', 'domain.register')->where('account_label', 'Second user (staff)')->exists(), 'registered domain remembers account B; audit has its label');
    ok(!str_contains(json_encode(j($r)), TOK_B) , 'register response has no token');

    // ---------- portal neutrality ----------
    $uA = ClientUser::create(['client_id' => $clientA->id, 'tenant_id' => $tenantA->id, 'name' => 'U nc-acc', 'email' => 'nc-acc-ua@example.test', 'password' => 'x-Secret-123', 'role' => 'admin', 'is_active' => true]);
    $prq = fn ($m) => req(Request::create('/x', 'GET'), $uA);
    fk(['api.name.com/*' => Http::response(dom('cahc-acc-test.com'))]);
    $pr = trap(fn () => app(PortalDomainController::class)->nameservers($prq('n'), $dA->fresh()));
    $ps = trap(fn () => app(PortalDomainController::class)->show($prq('s'), $dA->fresh()));
    $pj = str_replace(['ns1.name.com', 'ns2.name.com'], 'nsX', json_encode([j($pr), j($ps)])); // nameserver hostnames are data, not branding
    ok($pr->getStatusCode() === 200 && users() === ['owner'] && !preg_match('/name\.com|namecom|Owner account|Second user|account_id|' . TOK_A . '/i', $pj), 'portal reads via the domain account and shows no account/supplier wording');

    // ---------- delete ----------
    $r = nc($staffA, 'destroyAccount', [], [], $idB);
    ok($r->getStatusCode() === 409 && NameComAccount::find($idB) !== null && j($r)['linked_domains'] >= 2, 'deleting an account with linked domains needs explicit confirmation');
    $rq = Request::create('/x', 'DELETE', ['confirm_linked' => true]); req($rq, $staffA);
    $r = trap(fn () => app(NameComController::class)->destroyAccount($rq, $idB));
    ok($r->getStatusCode() === 200 && NameComAccount::find($idB) === null && NameComAccount::find($idA)->is_default && NameComAuditLog::where('action', 'account.delete')->where('account_label', 'Second user (staff)')->exists(), 'confirmed delete removes only local credentials; default intact; audited');
    fk(['api.name.com/*' => Http::response(dom('nassh-acc-test.com'))]);
    app(NameComDomainService::class)->nameservers($dB->fresh());
    ok(Http::recorded()->first()[0]->header('Authorization')[0] === basic('owner', TOK_A), 'after removal the domain falls back to the default account');
    // deleting the default promotes another
    fk(fakeByUser(['second' => []]));
    $idC = j(nc($staffA, 'storeAccount', ['label' => 'Third', 'username' => 'second', 'token' => TOK_B]))['data']['id'];
    $rq = Request::create('/x', 'DELETE', ['confirm_linked' => true]); req($rq, $staffA);
    trap(fn () => app(NameComController::class)->destroyAccount($rq, $idA));
    ok(NameComAccount::find($idC)->is_default === true, 'deleting the default promotes the remaining account');

    // ---------- allow-list unchanged ----------
    fk(['*' => Http::response([], 200)]);
    $refuse = function (string $m, string $p, bool $c = false) { try { NameComDriver::assertAllowed($m, $p, $c); return false; } catch (NameComApiException) { return true; } };
    foreach ([['DELETE', '/core/v1/domains/a.com'], ['PUT', '/core/v1/domains/a.com'], ['POST', '/core/v1/domains/a.com:renew'], ['POST', '/core/v1/domains/a.com:setContacts'],
        ['POST', '/core/v1/domains'], ['POST', '/core/v1/transfers'], ['GET', '/core/v1/account'], ['POST', '/core/v1/accounts'], ['GET', '/core/v1/accounts'], ['GET', '/core/v1/domains/a.com:getAuthCode'], ['POST', '/core/v1/domains/a.com/records']] as [$m, $p]) {
        ok($refuse($m, $p), "still refused $m $p");
    }
    ok(!$refuse('GET', '/core/v1/domains') && !$refuse('GET', '/core/v1/domains/a.com') && !$refuse('POST', '/core/v1/domains/a.com:setNameservers') && !$refuse('POST', '/core/v1/domains', true), 'allowed set unchanged');
    ok(hits() === 0, 'allow-list checks made no HTTP');

    // ---------- tenant isolation & permissions ----------
    $other = User::withoutGlobalScopes()->where('tenant_id', $tenantB->id)->first();
    if ($other) {
        auth()->setUser($other);
        ok(NameComAccount::count() === 0, 'tenant B cannot see tenant A accounts');
        $r = nc($other, 'updateAccount', ['label' => 'hijack'], [], $idC);
        ok($r->getStatusCode() === 404 && NameComAccount::withoutGlobalScopes()->find($idC)->label === 'Third', 'tenant B cannot update tenant A account');
        ok(nc($other, 'destroyAccount', [], [], $idC)->getStatusCode() === 404 && NameComAccount::withoutGlobalScopes()->find($idC) !== null, 'tenant B cannot delete tenant A account');
        ok(j(nc($other, 'accountOptions'))['data'] === [], 'tenant B options empty');
        ok(NameComAccount::findFor($tenantB->id, $idC) === null, 'findFor is tenant-bound');
        fk([]);
        $rB = app(\App\Services\Registrar\DomainRegistrarManager::class);
        try { $rB->namecomFor($tenantB->id, $idC); ok(false, 'tenant B cannot borrow A account'); } catch (\App\Exceptions\RegistrarApiException) { ok(hits() === 0, 'tenant B cannot resolve tenant A account id (no HTTP)'); }
    } else echo "SKIP no tenant B user\n";
    auth()->setUser($staffA);
    $routes = collect(app('router')->getRoutes())->filter(fn ($r) => str_starts_with($r->uri(), 'api/namecom'));
    $perm = fn ($r) => collect($r->gatherMiddleware())->first(fn ($m) => str_starts_with($m, 'permission:'));
    $acc = $routes->filter(fn ($r) => str_starts_with($r->uri(), 'api/namecom/accounts') && !str_contains($r->uri(), 'options'));
    ok($acc->count() === 5 && $acc->every(fn ($r) => $perm($r) === 'permission:domains.settings'), 'account CRUD/test routes require domains.settings');
    $imp = $routes->filter(fn ($r) => in_array($r->uri(), ['api/namecom/account-options', 'api/namecom/link-matched', 'api/namecom/domains', 'api/namecom/link']));
    ok($imp->count() === 4 && $imp->every(fn ($r) => $perm($r) === 'permission:domains.create'), 'import / bulk-link / options routes require domains.create');
    ok($routes->every(fn ($r) => !array_diff($r->methods(), ['GET', 'HEAD', 'POST', 'PUT', 'DELETE'])), 'no unexpected verbs on namecom routes');

    ok(!str_contains(implode("\n", $logged), TOK_A) && !str_contains(implode("\n", $logged), TOK_B), 'tokens never appear in application logs');
} catch (\Throwable $e) {
    $fail++; echo "EXCEPTION: " . $e->getMessage() . "\n" . $e->getFile() . ':' . $e->getLine() . "\n";
} finally {
    DB::rollBack();
}
echo $fail ? "\n$fail FAILED\n" : "\nALL PASSED\n";
exit($fail ? 1 : 0);
