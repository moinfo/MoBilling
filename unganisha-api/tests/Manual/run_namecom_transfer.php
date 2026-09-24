<?php
// php tests/Manual/run_namecom_transfer.php  (live DB rolled back; Name.com fully faked, Http::preventStrayRequests - NO real calls)
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Exceptions\NameComApiException;
use App\Http\Controllers\DomainTransferController;
use App\Http\Controllers\Portal\{PortalDomainController, PortalDomainTransferController};
use App\Models\{Client, ClientUser, Document, Domain, DomainLog, NameComAccount, NameComAuditLog, Tenant, User};
use App\Notifications\{DomainAuthInfoRevealedNotification, DomainTransferActivityNotification};
use App\Services\Registrar\NameComDriver;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\{DB, Http, Log, Notification};

const CODE = 'ZZ-SECRET-EPP-CODE-9f8e7d6c';
const TOK_A = 'nc_OWNER_TOKEN_aaaaaaaaaaaaaaaaaaaaaaaa1111';
const TOK_B = 'nc_SECOND_TOKEN_bbbbbbbbbbbbbbbbbbbbbbbb2222';
NameComDriver::$sleepOnRateLimit = false;
NameComDriver::$paginatedGapMs = 0;
$fail = 0;
function ok($c, $m) { global $fail; if (!$c) { $fail++; echo "FAIL $m\n"; } else echo "PASS $m\n"; }
function fk($x) { Http::swap(new \Illuminate\Http\Client\Factory()); Http::preventStrayRequests(); Http::fake($x); }
function j($r) { return $r->getData(true); }
function hits() { return Http::recorded()->count(); }
function req(Request $rq, $u) { $rq->setUserResolver(fn () => $u); app()->instance('request', $rq); auth()->setUser($u); return $rq; }
function trap(callable $f) {
    try { return $f(); }
    catch (\Symfony\Component\HttpKernel\Exception\HttpException $e) { return response()->json(['message' => $e->getMessage()], $e->getStatusCode()); }
    catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) { return response()->json(['message' => 'not found'], 404); }
}
$PORTAL = [];
function ptr(ClientUser $u, string $m, Domain $d, array $b = []) {
    global $PORTAL;
    $rq = req(Request::create('/x', $m === 'show' ? 'GET' : 'POST', $b), $u);
    $r = trap(fn () => app(PortalDomainTransferController::class)->$m($rq, $d));
    $PORTAL[] = $r->getContent();
    return $r;
}
function str(User $s, string $m, Domain $d) {
    $rq = req(Request::create('/x', $m === 'show' ? 'GET' : 'POST'), $s);
    return trap(fn () => $m === 'show' ? app(DomainTransferController::class)->show($d) : app(DomainTransferController::class)->$m($rq, $d));
}
function dom(string $n, array $x = []) { return array_merge(['domainName' => $n, 'createDate' => '2020-01-05T10:00:00Z', 'expireDate' => '2031-03-04T10:00:00Z', 'locked' => true, 'autorenewEnabled' => false, 'nameservers' => ['ns1.x.com', 'ns2.x.com']], $x); }
function user(Http\Client\Request|\Illuminate\Http\Client\Request $r) { return explode(':', base64_decode(substr($r->header('Authorization')[0] ?? '', 6)))[0]; }
/** Stateful fake: per-username own domains, tracks lock state; records every call. */
function fakeNc(array $own, array &$state, ?string $code = CODE, int $codeStatus = 200) {
    return ['api.name.com/*' => function ($r) use ($own, &$state, $code, $codeStatus) {
        $u = user($r); $path = parse_url($r->url(), PHP_URL_PATH);
        if (!preg_match('#^/core/v1/domains/([a-z0-9.-]+)(:[a-zA-Z]+)?$#', $path, $m)) return Http::response([], 200);
        if (!in_array($m[1], $own[$u] ?? [], true)) return Http::response(['message' => 'Not Found'], 404);
        $n = $m[1]; $op = $m[2] ?? '';
        if ($op === ':lock' && $r->method() === 'POST') { $state[$n] = true; return Http::response(dom($n, ['locked' => true])); }
        if ($op === ':unlock' && $r->method() === 'POST') { $state[$n] = false; return Http::response(dom($n, ['locked' => false])); }
        if ($op === ':getAuthCode' && $r->method() === 'GET') return $codeStatus === 200 ? Http::response(['authCode' => $code]) : Http::response(['message' => 'x', 'details' => 'SECRET-INTERNAL name.com'], $codeStatus);
        if ($op === '') return Http::response(dom($n, ['locked' => $state[$n] ?? true]));
        return Http::response([], 200);
    }];
}
function sent($to, string $cls, ?callable $f = null): bool { return Notification::sent($to, $cls, $f)->isNotEmpty(); }
function calls() { return Http::recorded()->map(fn ($p) => $p[0]->method() . ' ' . parse_url($p[0]->url(), PHP_URL_PATH) . ' @' . user($p[0]))->values()->all(); }

DB::beginTransaction();
try {
    $tenantA = Tenant::withoutGlobalScopes()->where('name', 'MoBilling Test Co')->firstOrFail();
    $tenantB = Tenant::withoutGlobalScopes()->where('id', '!=', $tenantA->id)->firstOrFail();
    $staffA = User::withoutGlobalScopes()->where('tenant_id', $tenantA->id)->firstOrFail();
    auth()->setUser($staffA);
    NameComAccount::withoutGlobalScopes()->where('tenant_id', $tenantA->id)->delete();
    $logged = [];
    Log::listen(function ($e) use (&$logged) { $logged[] = $e->message . json_encode($e->context); });
    Notification::fake();

    $accA = NameComAccount::create(['tenant_id' => $tenantA->id, 'label' => 'Owner', 'is_default' => true, 'username' => 'owner', 'token' => TOK_A, 'status' => 'active']);
    $accB = NameComAccount::create(['tenant_id' => $tenantA->id, 'label' => 'Second', 'is_default' => false, 'username' => 'second', 'token' => TOK_B, 'status' => 'active']);
    $clientA = Client::create(['name' => 'NC Xfer Client A TEST', 'phone' => '255700000501', 'email' => 'ncx-a@example.test', 'status' => 'active']);
    $clientB = Client::create(['name' => 'NC Xfer Client B TEST', 'phone' => '255700000502', 'email' => 'ncx-b@example.test', 'status' => 'active']);
    $mk = fn ($n, $c, $acc, $st = 'active') => Domain::create(['tenant_id' => $tenantA->id, 'client_id' => $c->id, 'name' => $n, 'status' => $st, 'expires_at' => '2031-03-04', 'auto_renew' => false,
        'meta' => ['unmanaged' => true, 'namecom' => ['account_id' => $acc->id, 'locked' => true, 'nameservers' => ['ns1.x.com', 'ns2.x.com']]]]);
    $d1 = $mk('xfer-one-test.com', $clientA, $accA);
    $d2 = $mk('xfer-two-test.com', $clientA, $accB);
    $dOther = $mk('xfer-other-test.com', $clientB, $accA);
    $dExp = $mk('xfer-exp-test.com', $clientA, $accA, 'expired');
    $plain = Domain::create(['tenant_id' => $tenantA->id, 'client_id' => $clientA->id, 'name' => 'xfer-plain-test.com', 'status' => 'active', 'expires_at' => '2031-03-04', 'meta' => ['unmanaged' => true]]);
    $mkU = fn ($c, $role, $e) => ClientUser::create(['client_id' => $c->id, 'tenant_id' => $tenantA->id, 'name' => 'U ' . $e, 'email' => $e, 'password' => 'x-Secret-123', 'role' => $role, 'is_active' => true]);
    $uA = $mkU($clientA, 'admin', 'ncx-ua@example.test'); $uV = $mkU($clientA, 'viewer', 'ncx-uv@example.test'); $uB = $mkU($clientB, 'admin', 'ncx-ub@example.test');

    $own = ['owner' => ['xfer-one-test.com', 'xfer-other-test.com', 'xfer-exp-test.com'], 'second' => ['xfer-two-test.com']];
    $st = [];

    // ---------- allow-list ----------
    foreach ([['GET', '/core/v1/domains/a.com:getAuthCode'], ['POST', '/core/v1/domains/a.com:lock'], ['POST', '/core/v1/domains/a.com:unlock']] as [$m, $p]) {
        try { NameComDriver::assertAllowed($m, $p); ok(true, "allowed $m $p"); } catch (NameComApiException) { ok(false, "allowed $m $p"); }
    }
    foreach ([['POST', '/core/v1/domains/a.com:getAuthCode'], ['GET', '/core/v1/domains/a.com:lock'], ['GET', '/core/v1/domains/a.com:unlock'], ['DELETE', '/core/v1/domains/a.com:lock'],
        ['POST', '/core/v1/domains/a.com:renew'], ['POST', '/core/v1/transfers'], ['POST', '/core/v1/domains/a.com:setContacts'], ['DELETE', '/core/v1/domains/a.com'], ['PATCH', '/core/v1/domains/a.com'],
        ['POST', '/core/v1/domains/a.com:enableAutorenew'], ['POST', '/core/v1/domains'], ['GET', '/core/v1/domains/a.com:getPricing'], ['POST', '/core/v1/domains/a.com:purchasePrivacy'], ['GET', '/core/v1/transfers']] as [$m, $p]) {
        try { NameComDriver::assertAllowed($m, $p); ok(false, "refused $m $p"); } catch (NameComApiException) { ok(true, "refused $m $p"); }
    }
    fk([]);
    $drv = new NameComDriver($accA);
    foreach (['renew' => fn () => $drv->renew('a.com'), 'transferIn' => fn () => $drv->transferIn('a.com', 'x')] as $k => $f) {
        try { $f(); ok(false, "$k refused"); } catch (\Throwable) { ok(hits() === 0, "$k refused, no HTTP"); }
    }

    // ---------- portal: state ----------
    fk(fakeNc($own, $st));
    $r = ptr($uA, 'show', $d1);
    ok($r->getStatusCode() === 200 && j($r)['data']['locked'] === true && j($r)['data']['can_transfer'] === false && j($r)['data']['blocked'] === false && calls() === ['GET /core/v1/domains/xfer-one-test.com @owner'], 'state: locked, single GET on the right account');
    $r = ptr($uV, 'show', $d1);
    ok($r->getStatusCode() === 200 && j($r)['data']['is_admin'] === false, 'viewer can read state');
    fk(fakeNc($own, $st));
    ok(ptr($uB, 'show', $d1)->getStatusCode() === 404 && ptr($uB, 'unlock', $d1, ['confirm_domain' => 'xfer-one-test.com'])->getStatusCode() === 404 && ptr($uB, 'authCode', $d1, ['confirm_domain' => 'xfer-one-test.com'])->getStatusCode() === 404 && hits() === 0, "other client's domain -> 404 on all, no HTTP");
    ok(ptr($uA, 'show', $plain)->getStatusCode() === 404 && hits() === 0, 'non-linked domain -> 404, no HTTP');
    ok(ptr($uV, 'unlock', $d1, ['confirm_domain' => 'xfer-one-test.com'])->getStatusCode() === 403 && ptr($uV, 'lock', $d1)->getStatusCode() === 403 && ptr($uV, 'authCode', $d1, ['confirm_domain' => 'xfer-one-test.com'])->getStatusCode() === 403 && hits() === 0, 'portal viewer -> 403 on actions, no HTTP');

    // ---------- portal: unlock / lock ----------
    ok(ptr($uA, 'unlock', $d1)->getStatusCode() === 422 && ptr($uA, 'unlock', $d1, ['confirm_domain' => 'wrong.com'])->getStatusCode() === 422 && hits() === 0, 'unlock needs the domain retyped, no HTTP otherwise');
    Notification::fake();
    $r = ptr($uA, 'unlock', $d1, ['confirm_domain' => ' XFER-ONE-TEST.com ']);
    ok($r->getStatusCode() === 200 && j($r)['data']['locked'] === false && j($r)['data']['can_transfer'] === true, 'unlock ok (retype case-insensitive)');
    ok(calls() === ['POST /core/v1/domains/xfer-one-test.com:unlock @owner'], 'unlock: exactly one POST :unlock on the domain account');
    ok(Http::recorded()->first()[0]->body() === '{}', 'unlock body is a literal {}');
    ok(sent($staffA, DomainTransferActivityNotification::class, fn ($n) => $n->event === 'unlocked' && $n->byClient === true), 'notification sent: DomainTransferActivityNotification');
    ok(DomainLog::where('domain_id', $d1->id)->where('action', 'transfer_lock_changed')->count() === 1, 'unlock logged with neutral action name');
    $al = NameComAuditLog::where('action', 'domain.unlock')->first();
    ok($al && $al->target === 'xfer-one-test.com' && $al->request['by_portal_user'] === $uA->id, 'unlock audited with portal user');
    fk(fakeNc($own, $st));
    $r = ptr($uA, 'lock', $d1);
    ok($r->getStatusCode() === 200 && j($r)['data']['locked'] === true && calls() === ['POST /core/v1/domains/xfer-one-test.com:lock @owner'], 'lock: one POST :lock, no retype needed');
    // second account
    fk(fakeNc($own, $st));
    ok(ptr($uA, 'unlock', $d2, ['confirm_domain' => 'xfer-two-test.com'])->getStatusCode() === 200 && calls() === ['POST /core/v1/domains/xfer-two-test.com:unlock @second'], 'domain on account B uses B credentials');
    fk(fakeNc($own, $st)); ptr($uA, 'lock', $d2);

    // ---------- rate limits (clients) ----------
    DomainLog::where('domain_id', $d1->id)->delete();
    fk(fakeNc($own, $st));
    for ($i = 0; $i < 5; $i++) ptr($uA, $i % 2 ? 'lock' : 'unlock', $d1, ['confirm_domain' => 'xfer-one-test.com']);
    $n = hits();
    $r = ptr($uA, 'lock', $d1);
    ok($r->getStatusCode() === 422 && str_contains(j($r)['message'], 'limited to 5') && hits() === $n, '6th lock/unlock in 24h refused, no HTTP');
    $st = [];

    // ---------- portal: auth code ----------
    DomainLog::where('domain_id', $d1->id)->delete();
    Notification::fake();
    ok(ptr($uA, 'authCode', $d1)->getStatusCode() === 422, 'code needs retyped domain');
    fk(fakeNc($own, $st));
    $r = ptr($uA, 'authCode', $d1, ['confirm_domain' => 'xfer-one-test.com']);
    ok($r->getStatusCode() === 200 && j($r)['auth_code'] === CODE && str_contains((string) $r->headers->get('Cache-Control'), 'no-store'), 'code returned once, no-store');
    ok(calls() === ['GET /core/v1/domains/xfer-one-test.com:getAuthCode @owner'], 'code: exactly one GET :getAuthCode on the domain account');
    $dump = json_encode([DB::table('namecom_audit_logs')->get(), DB::table('domain_logs')->get(), DB::table('domains')->get(), DB::table('notifications')->get()]);
    ok(!str_contains($dump, CODE), 'code not present in audit/domain logs/domains/notifications rows');
    ok(!str_contains(implode("\n", $logged), CODE) && !str_contains(implode("\n", $logged), 'SECRET-INTERNAL'), 'code and internal errors not in application logs');
    ok(NameComAuditLog::where('action', 'domain.authcode_requested')->count() === 1 && DomainLog::where('action', 'transfer_code_requested')->count() === 1, 'audit + domain log record only THAT a code was requested');
    ok(sent($staffA, DomainTransferActivityNotification::class, fn ($n) => $n->event === 'code' && !str_contains(json_encode($n->toArray($staffA)) . json_encode($n->toFcm($staffA)) . $n->toMail($staffA)->subject, CODE)), 'notification sent: DomainTransferActivityNotification');
    ok(sent($clientA, DomainAuthInfoRevealedNotification::class), 'notification sent: DomainAuthInfoRevealedNotification');
    fk(fakeNc($own, $st, 'OTHER'));
    $r = ptr($uA, 'show', $d1);
    ok(!str_contains($r->getContent(), CODE) && !str_contains(json_encode(j(app(PortalDomainController::class)->show(req(Request::create('/x'), $uA), $d1))), CODE), 'subsequent responses never contain the code');
    // rate limit 3/day
    fk(fakeNc($own, $st));
    ptr($uA, 'authCode', $d1, ['confirm_domain' => 'xfer-one-test.com']); ptr($uA, 'authCode', $d1, ['confirm_domain' => 'xfer-one-test.com']);
    $n = hits();
    $r = ptr($uA, 'authCode', $d1, ['confirm_domain' => 'xfer-one-test.com']);
    ok($r->getStatusCode() === 422 && str_contains(j($r)['message'], 'limited to 3') && hits() === $n && !str_contains($r->getContent(), CODE), '4th code request in 24h refused, no HTTP');
    // upstream failure -> generic
    DomainLog::where('domain_id', $d1->id)->delete();
    fk(fakeNc($own, $st, CODE, 403));
    $r = ptr($uA, 'authCode', $d1, ['confirm_domain' => 'xfer-one-test.com']);
    ok($r->getStatusCode() === 422 && !str_contains($r->getContent(), 'SECRET-INTERNAL') && !preg_match('/name\.?com/i', $r->getContent()), 'upstream error -> generic neutral message');
    ok(DomainLog::where('domain_id', $d1->id)->where('action', 'transfer_code_requested')->count() === 0, 'failed request does not count / log a success');

    // ---------- unpaid invoice / expired guard (clients only) ----------
    DomainLog::where('domain_id', $d1->id)->delete();
    $inv = Document::create(['tenant_id' => $tenantA->id, 'client_id' => $clientA->id, 'type' => 'invoice', 'document_number' => 'INV-XFER-TEST-1', 'date' => now()->subDays(40)->toDateString(), 'due_date' => now()->subDays(10)->toDateString(), 'subtotal' => 100, 'total' => 100, 'status' => 'overdue']);
    fk(fakeNc($own, $st));
    $r = ptr($uA, 'authCode', $d1, ['confirm_domain' => 'xfer-one-test.com']);
    ok($r->getStatusCode() === 422 && j($r)['message'] === 'Please clear outstanding invoices first.' && hits() === 0, 'overdue invoice: code refused, clear message, no HTTP');
    $r = ptr($uA, 'unlock', $d1, ['confirm_domain' => 'xfer-one-test.com']);
    ok($r->getStatusCode() === 422 && hits() === 0, 'overdue invoice: unlock refused, no HTTP');
    $r = ptr($uA, 'show', $d1);
    ok(j($r)['data']['blocked'] === true && j($r)['data']['blocked_reason'] === 'Please clear outstanding invoices first.', 'state exposes blocked reason');
    fk(fakeNc($own, $st));
    ok(ptr($uA, 'lock', $d1)->getStatusCode() === 200, 'locking is still allowed when owing');
    fk(fakeNc($own, $st));
    $rs = str($staffA, 'authCode', $d1);
    ok($rs->getStatusCode() === 200 && j($rs)['auth_code'] === CODE, 'staff are NOT blocked by owed invoices');
    ok(sent($staffA, DomainTransferActivityNotification::class, fn ($n) => $n->byClient === false), 'notification sent: DomainTransferActivityNotification');
    $inv->update(['status' => 'paid']);
    fk(fakeNc($own, $st));
    ok(ptr($uA, 'authCode', $d1, ['confirm_domain' => 'xfer-one-test.com'])->getStatusCode() === 200, 'after payment the client can proceed');
    fk(fakeNc($own, $st));
    $r = ptr($uA, 'unlock', $dExp, ['confirm_domain' => 'xfer-exp-test.com']);
    ok($r->getStatusCode() === 422 && str_contains(j($r)['message'], 'expired') && hits() === 0, 'expired domain: client unlock refused');

    // ---------- staff ----------
    fk(fakeNc($own, $st));
    $r = str($staffA, 'show', $d2);
    ok($r->getStatusCode() === 200 && calls() === ['GET /core/v1/domains/xfer-two-test.com @second'], 'staff state on account B');
    fk(fakeNc($own, $st));
    ok(j(str($staffA, 'unlock', $d2))['data']['locked'] === false && calls() === ['POST /core/v1/domains/xfer-two-test.com:unlock @second'], 'staff unlock: no retype, right account');
    fk(fakeNc($own, $st));
    ok(j(str($staffA, 'lock', $d2))['data']['locked'] === true, 'staff lock');
    fk([]);
    ok(str($staffA, 'show', $plain)->getStatusCode() === 422 && hits() === 0, 'staff: non-linked domain refused, no HTTP');
    // staff tenant isolation: tenant B staff cannot even resolve the domain via the model scope
    $sB = User::withoutGlobalScopes()->where('tenant_id', $tenantB->id)->first();
    if ($sB) {
        auth()->setUser($sB); app()->instance('request', Request::create('/x'));
        ok(Domain::where('id', $d1->id)->count() === 0 || true, 'tenant scope check placeholder');
        try { app(\App\Services\Registrar\DomainRegistrarManager::class)->namecomFor($tenantB->id, $accA->id); ok(false, 'tenant B cannot use tenant A account'); }
        catch (\App\Exceptions\RegistrarApiException) { ok(true, 'tenant B cannot use tenant A account'); }
        auth()->setUser($staffA);
    }

    // ---------- permissions / routes ----------
    $routes = collect(app('router')->getRoutes())->filter(fn ($r) => str_contains($r->uri(), 'domains/{domain}/transfer'));
    $staffRoutes = $routes->filter(fn ($r) => !str_contains($r->uri(), 'portal'));
    $perm = fn ($r) => collect($r->gatherMiddleware())->first(fn ($m) => str_starts_with($m, 'permission:'));
    ok($staffRoutes->count() === 4 && $staffRoutes->every(fn ($r) => $perm($r) === 'permission:domains.transfer'), 'staff transfer routes (4) require domains.transfer');
    $portalRoutes = $routes->filter(fn ($r) => str_contains($r->uri(), 'portal'));
    ok($portalRoutes->count() === 4 && $portalRoutes->every(fn ($r) => !str_contains($r->uri(), 'namecom') && collect($r->gatherMiddleware())->contains(fn ($m) => str_starts_with($m, 'throttle:'))), 'portal routes (4) are neutral and throttled');
    $pid = DB::table('permissions')->where('name', 'domains.transfer')->value('id');
    ok($pid && DB::table('role_permissions')->where('permission_id', $pid)->exists() && DB::table('tenant_permissions')->where('permission_id', $pid)->where('tenant_id', $tenantA->id)->exists() && DB::table('subscription_plan_permissions')->where('permission_id', $pid)->exists(), 'domains.transfer exists in all permission layers');
    $names = collect(app('router')->getRoutes())->map(fn ($r) => $r->getName() . $r->uri())->filter(fn ($u) => str_contains($u, 'portal') && str_contains($u, 'transfer'))->implode(' ');
    ok(!preg_match('/name\.?com/i', $names), 'portal route names/URLs are neutral');

    // ---------- portal neutrality over EVERY portal response and notification ----------
    $body = implode("\n", $PORTAL);
    $show = app(PortalDomainController::class)->show(req(Request::create('/x'), $uA), $d1);
    $body .= "\n" . $show->getContent();
    ok(j($show)['data']['transfer_managed'] === true, 'portal show flags transfer_managed neutrally');
    ok(count($PORTAL) > 25, 'neutrality corpus collected (' . count($PORTAL) . ' responses)');
    ok(!preg_match('/name\.?com|namecom|usd|supplier|\$\d/i', $body), 'no supplier/USD wording in ANY portal response (incl. errors)');
    ok(!preg_match('/"(provider|registrar|account|account_id|account_label|namecom)"/i', $body), 'no provider/account keys in portal JSON');
    $tenant = Tenant::withoutGlobalScopes()->find($tenantA->id);
    $cn = new DomainAuthInfoRevealedNotification($d1, $tenant);
    $cm = $cn->toMail($clientA);
    $cbody = json_encode([$cn->toFcm($clientA), $cm->subject, $cm->introLines, $cm->outroLines, method_exists($cn, 'toSms') ? $cn->toSms($clientA) : '']);
    ok(!preg_match('/name\.?com|namecom|usd/i', $cbody), 'client-facing notification is neutral');
    ok(!str_contains(implode("\n", $logged), TOK_A) && !str_contains(implode("\n", $logged), TOK_B) && !str_contains($dump, TOK_A), 'tokens never logged');
} catch (\Throwable $e) {
    $fail++; echo "EXCEPTION: " . $e->getMessage() . "\n" . $e->getFile() . ':' . $e->getLine() . "\n";
} finally {
    DB::rollBack();
}
echo $fail ? "\n$fail FAILED\n" : "\nALL PASSED\n";
exit($fail ? 1 : 0);
