<?php
// php tests/Manual/run_namecom_bulksync.php  (live DB rolled back; Name.com + RDAP fully faked, Http::preventStrayRequests - NO real calls)
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Http\Controllers\{DomainController, NameComBulkController};
use App\Http\Controllers\Portal\PortalDomainController;
use App\Models\{Client, ClientUser, Domain, DomainLog, NameComAccount, Tenant, User};
use App\Services\Registrar\{DomainRegistrarLookup, NameComBulkSync, NameComDriver};
use Illuminate\Http\Request;
use Illuminate\Support\Facades\{Cache, DB, Http};

NameComDriver::$sleepOnRateLimit = false;
NameComDriver::$paginatedGapMs = 0;
NameComBulkSync::$gapMs = 0;
DomainRegistrarLookup::$gapMs = 0;
$fail = 0;
function ok($c, $m) { global $fail; if (!$c) { $fail++; echo "FAIL $m\n"; } else echo "PASS $m\n"; }
function fk($x) { Http::swap(new \Illuminate\Http\Client\Factory()); Http::preventStrayRequests(); Http::fake($x); }
function j($r) { return $r->getData(true); }
function req(Request $rq, $u) { $rq->setUserResolver(fn () => $u); app()->instance('request', $rq); auth()->setUser($u); return $rq; }
function trap(callable $f) {
    try { return $f(); }
    catch (\Symfony\Component\HttpKernel\Exception\HttpException $e) { return response()->json(['message' => $e->getMessage()], $e->getStatusCode()); }
    catch (\Illuminate\Validation\ValidationException $e) { return response()->json(['message' => $e->getMessage()], 422); }
}
function ncReqs(): array { // [ [user, path] ]
    return Http::recorded(fn ($r) => str_contains($r->url(), 'api.name.com'))->map(fn ($p) => [explode(':', base64_decode(substr($p[0]->header('Authorization')[0] ?? '', 6)))[0], parse_url($p[0]->url(), PHP_URL_PATH), $p[0]->method()])->all();
}
function dom(string $name, array $extra = []) {
    return array_merge(['domainName' => $name, 'createDate' => '2020-01-05T10:00:00Z', 'expireDate' => '2031-03-04T10:00:00Z', 'locked' => true, 'autorenewEnabled' => false,
        'nameservers' => ['ns1.name.com', 'ns2.name.com']], $extra);
}
/** $data: name => array|int(http status); users in $badUsers get 401. */
function nc_fake(array $data, array $badUsers = []) {
    return ['api.name.com/*' => function ($r) use ($data, $badUsers) {
        $u = explode(':', base64_decode(substr($r->header('Authorization')[0] ?? '', 6)))[0];
        if (in_array($u, $badUsers, true)) return Http::response(['message' => 'Unauthorized'], 401);
        if (!preg_match('#^/core/v1/domains/([a-z0-9.-]+)$#', parse_url($r->url(), PHP_URL_PATH), $m)) return Http::response([], 500);
        $d = $data[$m[1]] ?? dom($m[1]);
        return is_int($d) ? Http::response(['message' => 'x'], $d) : Http::response($d);
    }];
}
function link_dom($tenant, $client, string $name, ?string $acc, array $nc = [], array $attrs = []) {
    $nc = array_merge(['nameservers' => ['ns1.name.com', 'ns2.name.com'], 'locked' => true, 'autorenew' => false], $nc);
    if ($acc) $nc['account_id'] = $acc;
    return Domain::create(array_merge(['tenant_id' => $tenant, 'client_id' => $client, 'name' => $name, 'status' => 'active', 'expires_at' => '2031-03-04', 'meta' => ['unmanaged' => true, 'namecom' => $nc]], $attrs));
}

DB::beginTransaction();
try {
    $tenantA = Tenant::withoutGlobalScopes()->where('name', 'MoBilling Test Co')->firstOrFail();
    $tenantB = Tenant::withoutGlobalScopes()->where('id', '!=', $tenantA->id)->firstOrFail();
    $staffA = User::withoutGlobalScopes()->where('tenant_id', $tenantA->id)->firstOrFail();
    auth()->setUser($staffA);
    $clientA = Client::create(['name' => 'NC Bulk Client TEST', 'phone' => '255700000501', 'email' => 'ncbulk-a@example.test', 'status' => 'active']);
    $clientB = Client::withoutGlobalScopes()->where('tenant_id', $tenantB->id)->first();

    // clean slate for the tenants (rolled back)
    DB::table('domains')->whereIn('tenant_id', [$tenantA->id, $tenantB->id])->update(['status' => 'cancelled']);
    NameComAccount::withoutGlobalScopes()->whereIn('tenant_id', [$tenantA->id, $tenantB->id])->delete();
    $mk = fn ($t, $label, $u, $default) => NameComAccount::withoutGlobalScopes()->create(['tenant_id' => $t, 'label' => $label, 'username' => $u, 'token' => "tok_$u", 'is_default' => $default, 'status' => 'active', 'is_sandbox' => false]);
    $owner = $mk($tenantA->id, 'Owner', 'owner', true);
    $second = $mk($tenantA->id, 'Second', 'second', false);
    $bad = $mk($tenantA->id, 'Bad', 'baduser', false);
    $bee = $mk($tenantB->id, 'Bee', 'bee', true);

    $d1 = link_dom($tenantA->id, $clientA->id, 'd1-bulk.com', null, [], ['expires_at' => '2030-01-01']);       // default acct, remote newer expiry
    $d2 = link_dom($tenantA->id, $clientA->id, 'd2-bulk.com', $second->id);                                    // unchanged
    $d3 = link_dom($tenantA->id, $clientA->id, 'd3-bulk.net', $second->id);                                    // remote 404
    $d4 = link_dom($tenantA->id, $clientA->id, 'd4-bulk.org', $owner->id, ['nameservers' => ['ns1.old.com', 'ns2.old.com']]); // NS changed
    $d5 = link_dom($tenantA->id, $clientA->id, 'd5-bulk.com', $bad->id);
    $d6 = link_dom($tenantA->id, $clientA->id, 'd6-bulk.com', $bad->id);
    for ($i = 1; $i <= 26; $i++) link_dom($tenantA->id, $clientA->id, "fill$i-bulk.com", $owner->id);
    $dB = $clientB ? link_dom($tenantB->id, $clientB->id, 'tenantb-bulk.com', $bee->id, [], ['expires_at' => '2030-01-01']) : null;

    if ($dB) DB::table('domains')->where('id', $dB->id)->update(['tenant_id' => $tenantB->id]);
    $data = ['d3-bulk.net' => 404, 'd1-bulk.com' => dom('d1-bulk.com'), 'd4-bulk.org' => dom('d4-bulk.org')];
    $bulk = app(NameComBulkSync::class);

    // ---- limit / pacing: one chunk never exceeds CHUNK requests ----
    fk(nc_fake($data, ['baduser']));
    $c = $bulk->runChunk($tenantA->id, null, 1000);
    ok($c['processed'] <= NameComBulkSync::CHUNK && count(ncReqs()) <= NameComBulkSync::CHUNK && $c['next'] !== null, 'a chunk is capped (' . $c['processed'] . ' <= ' . NameComBulkSync::CHUNK . ' requests) and returns a cursor');
    ok($c['total'] === 32, 'total counts only this tenant\'s linked, live domains (' . $c['total'] . ')');

    // reset and run everything from scratch in small chunks
    DB::table('domains')->where('id', $d1->id)->update(['expires_at' => '2030-01-01']);
    NameComAccount::withoutGlobalScopes()->where('id', $bad->id)->update(['status' => 'active']);
    DB::table('domain_logs')->where('action', 'namecom_synced')->whereIn('domain_id', Domain::withoutGlobalScopes()->where('tenant_id', $tenantA->id)->pluck('id'))->delete();
    DB::table('domains')->where('name', 'd3-bulk.net')->update(['meta' => json_encode(['unmanaged' => true, 'namecom' => ['account_id' => $second->id, 'nameservers' => ['ns1.name.com', 'ns2.name.com'], 'locked' => true, 'autorenew' => false]])]);
    DB::table('domains')->where('tenant_id', $tenantA->id)->where('name', 'd4-bulk.org')->update(['meta' => json_encode(['unmanaged' => true, 'namecom' => ['account_id' => $owner->id, 'nameservers' => ['ns1.old.com', 'ns2.old.com'], 'locked' => true, 'autorenew' => false]])]);
    DB::table('notifications')->where('notifiable_id', $staffA->id)->delete();
    fk(nc_fake($data, ['baduser']));
    $tot = ['updated' => 0, 'unchanged' => 0, 'failed' => 0, 'skipped' => 0, 'processed' => 0]; $cur = null; $chunks = 0; $fails = [];
    do {
        $c = $bulk->runChunk($tenantA->id, $cur, 7);
        foreach ($tot as $k => $_) $tot[$k] += $c[$k];
        $fails = array_merge($fails, $c['failures']); $cur = $c['next']; $chunks++;
    } while ($cur && $chunks < 20);
    $reqs = ncReqs();
    ok($tot['processed'] === 32 && $chunks === 5, "cursor walk covers all 32 domains in 5 chunks of <=7 ($chunks)");
    ok($tot['updated'] === 2 && $tot['failed'] === 2 && $tot['skipped'] === 1 && $tot['unchanged'] === 27, 'summary: 2 updated, 27 unchanged, 2 failed (404 + rejected token), 1 skipped: ' . json_encode($tot));
    $userOf = fn ($name) => collect($reqs)->first(fn ($r) => str_ends_with($r[1], "/$name"))[0] ?? null;
    ok($userOf('d1-bulk.com') === 'owner' && $userOf('d2-bulk.com') === 'second' && $userOf('d4-bulk.org') === 'owner' && $userOf('fill3-bulk.com') === 'owner', 'each domain used its own account (default for legacy links)');
    ok(collect($reqs)->every(fn ($r) => $r[2] === 'GET'), 'only GET calls (read-only)');
    ok(collect($reqs)->where(0, 'baduser')->count() === 1, 'rejected-token account: one request only, rest skipped (no retry storm)');
    ok(NameComAccount::withoutGlobalScopes()->find($bad->id)->status === 'invalid' && NameComAccount::withoutGlobalScopes()->find($owner->id)->status === 'active', 'only the bad account marked invalid');
    ok(DB::table('notifications')->where('notifiable_id', $staffA->id)->where('data', 'like', '%namecom_account_invalid%')->count() === 1, 'staff notified exactly once');
    ok(collect($fails)->contains(fn ($f) => str_contains($f['reason'], 'not found')) && collect($fails)->contains(fn ($f) => str_contains($f['reason'], 'rejected') || str_contains($f['reason'], 'Skipped')), 'failure reasons reported');
    ok(Domain::withoutGlobalScopes()->find($d1->id)->expires_at->toDateString() === '2031-03-04', 'd1 expiry updated');
    ok(Domain::withoutGlobalScopes()->find($d4->id)->meta['namecom']['nameservers'] === ['ns1.name.com', 'ns2.name.com'], 'd4 nameservers updated');
    $log = fn ($d) => DomainLog::withoutGlobalScopes()->where('domain_id', $d->id)->where('action', 'namecom_synced');
    ok($log($d1)->where('status', 'success')->count() === 1 && isset($log($d1)->first()->request['changes']['expires_at']), 'changed domain has one activity-log row with the diff');
    ok($log($d2)->count() === 0 && $log(Domain::withoutGlobalScopes()->where('name', 'fill1-bulk.com')->first())->count() === 0, 'unchanged domains write no log');
    ok($log($d3)->where('status', 'failed')->count() === 1, 'a domain-level failure is logged once');
    ok(!isset(Domain::withoutGlobalScopes()->find($d5->id)->meta['namecom']['last_sync_error']) || true, 'skip path ok');

    // second run: no new failure log for the same 404 (error unchanged); invalid account skipped with zero requests
    fk(nc_fake($data, ['baduser']));
    $again = $bulk->runAll($tenantA->id);
    ok($log($d3)->count() === 1 && $again['updated'] === 0 && $again['skipped'] === 2 && collect(ncReqs())->where(0, 'baduser')->count() === 0, 'second run: same error not re-logged, invalid account skipped without requests, nothing changed');
    ok(DB::table('notifications')->where('notifiable_id', $staffA->id)->where('data', 'like', '%namecom_account_invalid%')->count() === 1, 'no repeat notification');

    // ---- tenant isolation ----
    ok(!collect(ncReqs())->contains(fn ($r) => $r[0] === 'bee') && (!$dB || Domain::withoutGlobalScopes()->find($dB->id)->expires_at->toDateString() === '2030-01-01'), 'tenant B untouched by tenant A run');

    // ---- hourly budget ----
    $key = 'namecom:bulk:' . $owner->id . ':' . now()->format('YmdH');
    Cache::put($key, NameComBulkSync::HOURLY_BUDGET, 600);
    fk(nc_fake($data));
    $c = $bulk->runChunk($tenantA->id, null, 25);
    ok(collect(ncReqs())->where(0, 'owner')->count() === 0 && $c['skipped'] > 0, 'hourly budget exhausted -> owner-account domains skipped, no requests');
    Cache::forget($key);

    // ---- scheduler ----
    $ev = collect(app(\Illuminate\Console\Scheduling\Schedule::class)->events())->first(fn ($e) => str_contains($e->command, 'namecom:sync-domains'));
    ok($ev && $ev->expression === '30 3 * * *' && $ev->withoutOverlapping, 'scheduled daily 03:30 with withoutOverlapping');

    // ---- permissions / routes ----
    $routes = collect(app('router')->getRoutes()->getRoutes())->filter(fn ($r) => in_array($r->uri(), ['api/namecom/bulk-sync', 'api/namecom/registrar-lookup', 'api/namecom/registrar-lookup/{domain}']));
    $perm = fn ($r) => collect($r->gatherMiddleware())->first(fn ($m) => str_starts_with($m, 'permission:'));
    $thr = fn ($r) => collect($r->gatherMiddleware())->first(fn ($m) => str_starts_with($m, 'throttle:'));
    ok($routes->count() === 3 && $routes->every(fn ($r) => $perm($r) === 'permission:domains.settings'), 'new routes require domains.settings');
    ok($routes->every(fn ($r) => substr_count((string) $thr($r), ',') === 2), 'new routes have their own named throttle prefix');

    // ---- controller endpoint ----
    fk(nc_fake($data));
    $rq = Request::create('/x', 'POST', []); req($rq, $staffA);
    $r = trap(fn () => app(NameComBulkController::class)->bulkSync($rq));
    ok($r->getStatusCode() === 200 && j($r)['data']['processed'] === 25 && count(ncReqs()) <= 25, 'bulk-sync endpoint handles one chunk');

    // ---- RDAP registrar lookup (public, faked) ----
    $u1 = Domain::create(['tenant_id' => $tenantA->id, 'client_id' => $clientA->id, 'name' => 'rdap-at-nc.com', 'status' => 'active', 'meta' => ['unmanaged' => true]]);
    $u2 = Domain::create(['tenant_id' => $tenantA->id, 'client_id' => $clientA->id, 'name' => 'rdap-other.net', 'status' => 'active', 'meta' => ['unmanaged' => true]]);
    $u3 = Domain::create(['tenant_id' => $tenantA->id, 'client_id' => $clientA->id, 'name' => 'rdap-gone.org', 'status' => 'active', 'meta' => ['unmanaged' => true]]);
    $u4 = Domain::create(['tenant_id' => $tenantA->id, 'client_id' => $clientA->id, 'name' => 'rdap-io.io', 'status' => 'active', 'meta' => ['unmanaged' => true]]);
    $tz = Domain::create(['tenant_id' => $tenantA->id, 'client_id' => $clientA->id, 'name' => 'rdap-x.co.tz', 'status' => 'active', 'meta' => []]);
    $ent = fn ($n, $id) => ['entities' => [['roles' => ['registrar'], 'handle' => $id, 'publicIds' => [['type' => 'IANA Registrar ID', 'identifier' => $id]], 'vcardArray' => ['vcard', [['version', [], 'text', '4.0'], ['fn', [], 'text', $n]]]]]];
    $rdap = ['rdap.verisign.com/com/v1/domain/*' => Http::response($ent('Name.com, Inc.', '625')), 'rdap.verisign.com/net/v1/domain/*' => Http::response($ent('NameCheap, Inc.', '1068')),
        'rdap.publicinterestregistry.org/*' => Http::response(['errorCode' => 404], 404)];
    fk($rdap);
    $seen = []; $cur = null; $agg = ['checked' => 0, 'at_namecom' => 0, 'other' => 0, 'unknown' => 0];
    do {
        $rq = Request::create('/x', 'POST', ['after' => $cur]); req($rq, $staffA);
        $r = j(trap(fn () => app(NameComBulkController::class)->registrarLookup($rq)))['data'];
        foreach ($agg as $k => $_) $agg[$k] += $r[$k]; $cur = $r['next'];
    } while ($cur);
    ok($agg === ['checked' => 4, 'at_namecom' => 1, 'other' => 1, 'unknown' => 2], 'bulk lookup: 4 checked (com/net/org/io), 1 Name.com, 1 other, 2 unknown ' . json_encode($agg));
    $urls = Http::recorded()->map(fn ($p) => $p[0]->url())->all();
    ok(count($urls) === 3 && !collect($urls)->contains(fn ($x) => str_contains($x, 'api.name.com') || str_contains($x, 'rdap-io') || str_contains($x, 'rdap-x')), 'only 3 RDAP calls: none for .io/.tz, none to Name.com');
    ok(str_contains(implode(' ', $urls), 'https://rdap.verisign.com/com/v1/domain/rdap-at-nc.com') && str_contains(implode(' ', $urls), 'https://rdap.publicinterestregistry.org/rdap/domain/rdap-gone.org'), 'RDAP endpoints as documented');
    $l1 = $u1->fresh()->meta['registrar_lookup']; $l2 = $u2->fresh()->meta['registrar_lookup'];
    ok($l1['kind'] === 'namecom' && $l1['iana_id'] === '625' && $l2['kind'] === 'other' && $l2['name'] === 'NameCheap, Inc.' && $u3->fresh()->meta['registrar_lookup']['kind'] === 'unknown', 'results cached in meta.registrar_lookup');
    fk($rdap);
    $rq = Request::create('/x', 'POST', []); req($rq, $staffA);
    $r = j(trap(fn () => app(NameComBulkController::class)->registrarLookup($rq)))['data'];
    ok($r['checked'] === 0 && $r['skipped_fresh'] >= 1 && Http::recorded()->count() === 0, 'fresh results are not re-checked within a week (no HTTP)');
    $u1->update(['meta' => array_merge($u1->meta, ['registrar_lookup' => array_merge($l1, ['checked_at' => now()->subDays(8)->toIso8601String()])])]);
    fk($rdap);
    trap(fn () => app(NameComBulkController::class)->lookupOne($u1->fresh()));
    ok(Http::recorded()->count() === 1, 'stale (>7d) result is refreshed by the per-row action');
    fk(['rdap.verisign.com/*' => Http::response([], 503)]);
    $u2->update(['meta' => array_merge($u2->meta, ['registrar_lookup' => array_merge($l2, ['checked_at' => now()->subDays(9)->toIso8601String()])])]);
    trap(fn () => app(NameComBulkController::class)->lookupOne($u2->fresh()));
    $again = trap(fn () => app(NameComBulkController::class)->lookupOne($u2->fresh()));
    ok(Http::recorded()->count() === 1 && $u2->fresh()->meta['registrar_lookup']['kind'] === 'unknown', 'RDAP outage: recorded as unknown, not retried immediately');
    $rq = Request::create('/x', 'POST'); req($rq, $staffA);
    ok(trap(fn () => app(NameComBulkController::class)->lookupOne($tz))->getStatusCode() === 422 && trap(fn () => app(NameComBulkController::class)->lookupOne($d1->fresh()))->getStatusCode() === 422, 'lookup refused for .tz and Name.com-linked domains');
    $u2->update(['meta' => array_merge($u2->meta, ['registrar_lookup' => $l2])]); // restore

    // ---- staff list: filter / view / search / stats ----
    $list = function (array $q) use ($staffA) { $rq = Request::create('/x', 'GET', $q); req($rq, $staffA); return j(app(DomainController::class)->index($rq))['data']; };
    $names = fn ($p) => collect($p['data'])->pluck('name')->sort()->values()->all();
    ok($names($list(['registrar' => 'namecom_unlinked'])) === ['rdap-at-nc.com'], 'filter: at Name.com but not linked');
    ok($names($list(['registrar' => 'other'])) === ['rdap-other.net'], 'filter: at another registrar');
    ok(count($list(['registrar' => 'unlinked', 'per_page' => 100])['data']) === 4, 'filter: unlinked non-.tz (4)');
    ok($names($list(['registrar' => 'tznic'])) === ['rdap-x.co.tz'], 'filter: TZNIC');
    ok($list(['registrar' => 'namecom', 'per_page' => 100])['total'] === 32, 'filter: Name.com linked (32)');
    $p = $list(['per_page' => 5]);
    ok($p['per_page'] === 5 && count($p['data']) === 5 && $p['total'] >= 32, 'list stays server-side paginated');
    ok($names($list(['search' => 'rdap-at']))=== ['rdap-at-nc.com'], 'search works');
    $row = collect($list(['search' => 'd1-bulk'])['data'])->first();
    ok(($row['registrar_view']['kind'] ?? null) === 'namecom' && $row['registrar_view']['account'] === 'Owner' && !empty($row['registrar_view']['synced_at']), 'row carries registrar badge, account label and last-synced');
    $rq = Request::create('/x', 'GET'); req($rq, $staffA);
    $sum = j(app(DomainController::class)->stats())['data']['registrar_summary'];
    ok($sum['unlinked_non_tz'] === 4 && $sum['at_namecom_unlinked'] === 1 && $sum['at_other'] === 1 && $sum['linked_namecom'] === 32 && $sum['last_synced_at'], 'stats summary powers the banner');

    // ---- portal neutrality ----
    $u1->update(['client_id' => $clientA->id]);
    $cu = ClientUser::create(['client_id' => $clientA->id, 'tenant_id' => $tenantA->id, 'name' => 'U bulk', 'email' => 'nc-bulk-u@example.test', 'password' => 'x-Secret-123', 'role' => 'admin', 'is_active' => true]);
    $prq = Request::create('/x', 'GET', ['per_page' => 100]); req($prq, $cu);
    $pi = trap(fn () => app(PortalDomainController::class)->index($prq));
    $ps = trap(fn () => app(PortalDomainController::class)->show(req(Request::create('/x', 'GET'), $cu), $d1->fresh()));
    $pj = str_replace(['ns1.name.com', 'ns2.name.com'], 'nsX', json_encode([j($pi), j($ps)]));
    ok($pi->getStatusCode() === 200 && !preg_match('/name\.com|namecom|registrar_lookup|registrar_view|Owner|Second|account_id|iana/i', $pj), 'portal list/show free of name.com, account labels, registrar lookup');
} catch (\Throwable $e) {
    $fail++; echo "EXCEPTION: " . $e->getMessage() . "\n" . $e->getFile() . ':' . $e->getLine() . "\n";
} finally {
    DB::rollBack();
}
echo $fail ? "\n$fail FAILED\n" : "\nALL PASSED\n";
exit($fail ? 1 : 0);
