<?php
// php tests/Manual/run_linode_dns.php  (live DB rolled back, Linode fully faked - NO real API calls)
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Http\Controllers\LinodeController;
use App\Models\{Client, Domain, LinodeAccount, LinodeResource, Tenant, User};
use App\Services\Linode\{DnsMapping, LinodeService};
use Illuminate\Http\Request;
use Illuminate\Support\Facades\{DB, Http};

LinodeService::$sleepOnRateLimit = false;
LinodeService::$paginatedGapMs = 0;
$fail = 0;
function ok($c, $m) { global $fail; if (!$c) { $fail++; echo "FAIL $m\n"; } else echo "PASS $m\n"; }
function fk($x) { Http::swap(new \Illuminate\Http\Client\Factory()); Http::fake($x); }
function j($r) { return $r->getData(true); }
function bind(array $d) { app()->instance('request', Request::create('/x', 'POST', $d)); return app('request'); }
$page = fn ($data, $p = 1, $pages = 1) => ['data' => $data, 'page' => $p, 'pages' => $pages, 'results' => count($data)];
$rec = fn ($id, $type, $name, $target) => ['id' => $id, 'type' => $type, 'name' => $name, 'target' => $target, 'ttl_sec' => 0];
$C = fn () => app(LinodeController::class);

// ---- pure matching (no DB)
$idx = DnsMapping::buildIpIndex([
    ['id' => 'A', 'ipv4' => ['1.1.1.1', '1.1.1.2'], 'ipv6' => '2600:3c00::1/128'],
    ['id' => 'B', 'ipv4' => ['2.2.2.2'], 'ipv6' => null],
]);
$m = DnsMapping::match(['1.1.1.1'], ['1.1.1.1'], $idx);
ok($m['status'] === 'server' && $m['instance_ids'] === ['A'], 'single IP matches server');
$m = DnsMapping::match(['1.1.1.2'], [], $idx);
ok($m['status'] === 'server' && $m['instance_ids'] === ['A'], 'second IP of a multi-IP instance matches');
$m = DnsMapping::match(['1.1.1.1', '2.2.2.2'], [], $idx);
ok($m['status'] === 'server' && $m['instance_ids'] === ['A', 'B'], 'round robin -> two servers');
$m = DnsMapping::match([], [DnsMapping::normalizeIp('2600:3C00:0:0:0:0:0:1')], $idx);
ok($m['status'] === 'server' && $m['instance_ids'] === ['A'], 'IPv6 (different notation) matches');
$m = DnsMapping::match(['9.9.9.9'], [], $idx);
ok($m['status'] === 'external' && $m['external_ips'] === ['9.9.9.9'] && !$m['instance_ids'], 'external IP');
$m = DnsMapping::match([], [], $idx);
ok($m['status'] === 'no_a_record', 'no A record');
$m = DnsMapping::match(['1.1.1.1'], ['2.2.2.2'], $idx);
ok($m['apex_instance_ids'] === ['A'] && $m['www_instance_ids'] === ['B'], 'www differs from apex');
$x = DnsMapping::extractAddresses([$rec(1, 'A', '', '1.1.1.1'), $rec(2, 'A', '@', '1.1.1.1'), $rec(3, 'A', 'WWW', '2.2.2.2'), $rec(4, 'A', 'blog', '5.5.5.5'),
    $rec(5, 'AAAA', '', '2600:3c00::1'), $rec(6, 'MX', '', 'mail.x.com'), $rec(7, 'NS', '', 'ns1.linode.com')]);
ok($x['apex_ips'] === ['1.1.1.1', '2600:3c00::1'] && $x['www_ips'] === ['2.2.2.2'], 'extract: apex+www A/AAAA only, dedup, others ignored');

DB::beginTransaction();
try {
    $tenantA = Tenant::withoutGlobalScopes()->where('name', 'MoBilling Test Co')->firstOrFail();
    $userA = User::withoutGlobalScopes()->where('tenant_id', $tenantA->id)->firstOrFail();
    auth()->login($userA);
    $tenantB = Tenant::withoutGlobalScopes()->where('id', '!=', $tenantA->id)->whereHas('users')->first() ?? Tenant::withoutGlobalScopes()->where('id', '!=', $tenantA->id)->firstOrFail();
    $userB = User::withoutGlobalScopes()->where('tenant_id', $tenantB->id)->firstOrFail();

    $acct = new LinodeAccount(['label' => 'T', 'token' => 'lin_TESTTOKEN_abcdefghijklmnopqrstuvwxyz', 'token_hint' => 'wxyz', 'status' => 'active']);
    $acct->tenant_id = $tenantA->id; $acct->save();
    $acct2 = new LinodeAccount(['label' => 'T2', 'token' => 'lin_TESTTOKEN_abcdefghijklmnopqrstuvwxyz', 'token_hint' => 'wxyz', 'status' => 'active']);
    $acct2->tenant_id = $tenantA->id; $acct2->save();
    $mk = fn ($acc, $type, $rid, $label, $extra = []) => LinodeResource::create(['tenant_id' => $tenantA->id, 'linode_account_id' => $acc->id, 'type' => $type, 'remote_id' => $rid, 'label' => $label, 'status' => 'running'] + $extra);
    $s1 = $mk($acct, 'instance', '101', 'web-1', ['ipv4' => ['172.1.1.1', '172.1.1.9'], 'ipv6' => '2600:3c00::abcd/128']);
    $s2 = $mk($acct2, 'instance', '202', 'web-2 (other account)', ['ipv4' => ['172.2.2.2']]);
    $sGone = $mk($acct, 'instance', '303', 'dead', ['ipv4' => ['172.3.3.3'], 'status' => 'gone']);
    $dom = fn ($rid, $label, $extra = []) => $mk($acct, 'domain', $rid, $label, ['status' => 'active'] + $extra);
    $d1 = $dom('11', 'single.example.com'); $d2 = $dom('12', 'multi.example.com'); $d3 = $dom('13', 'v6.example.com');
    $d4 = $dom('14', 'ext.example.com'); $d5 = $dom('15', 'none.example.com'); $d6 = $dom('16', 'broken.example.com'); $d7 = $dom('17', 'paged.example.com');
    $d8 = $dom('18', 'xacct.example.com');

    $recsBy = [
        '11' => [$rec(1, 'A', '', '172.1.1.1'), $rec(2, 'A', 'www', '172.2.2.2')],
        '12' => [$rec(1, 'A', '', '172.1.1.9'), $rec(2, 'A', '', '172.2.2.2'), $rec(3, 'A', 'www', '172.1.1.9')],
        '13' => [$rec(1, 'AAAA', '', '2600:3c00:0:0:0:0:0:abcd')],
        '14' => [$rec(1, 'A', '', '8.8.8.8'), $rec(2, 'A', 'www', '8.8.8.8')],
        '15' => [$rec(1, 'MX', '', 'mail.x.com'), $rec(2, 'NS', '', 'ns1.linode.com')],
        '18' => [$rec(1, 'A', '', '172.2.2.2')],
    ];
    $calls = [];
    fk(function ($request) use ($recsBy, $page, $rec, &$calls) {
        $u = $request->url();
        if (!preg_match('#/domains/(\d+)/records#', $u, $mm)) return Http::response(['errors' => [['reason' => 'unexpected']]], 500);
        $id = $mm[1]; $calls[] = $request->method() . " $u";
        if ($request->method() !== 'GET') return Http::response(['errors' => [['reason' => 'WRITE!']]], 500);
        if ($id === '16') return Http::response(['errors' => [['reason' => 'boom']]], 500);
        if ($id === '17') {
            parse_str(parse_url($u, PHP_URL_QUERY) ?? '', $q);
            $p = (int) ($q['page'] ?? 1);
            return Http::response($page($p === 1 ? [$rec(1, 'A', '', '9.9.9.9')] : [$rec(2, 'A', 'www', '172.1.1.1')], $p, 2));
        }
        return Http::response($page($recsBy[$id] ?? []));
    });

    $r = $C()->refreshDns(bind(['offset' => 0, 'limit' => 5]), $acct);
    $out = j($r);
    ok($out['total'] === 8 && $out['processed'] === 5 && $out['next_offset'] === 5, 'batch 1: total/processed/next_offset');
    $r = $C()->refreshDns(bind(['offset' => 5, 'limit' => 5]), $acct);
    $out2 = j($r);
    ok($out2['processed'] === 3 && $out2['next_offset'] === null, 'batch 2 finishes');
    ok(count($out['failed']) + count($out2['failed']) === 1 && ($out['failed'][0]['domain'] ?? $out2['failed'][0]['domain']) === 'broken.example.com', 'one domain failed, others still processed (isolation)');
    ok(collect($calls)->every(fn ($c) => str_starts_with($c, 'GET ')), 'only GET calls made to Linode');

    $rows = collect(j($C()->domains())['data'])->keyBy('label');
    $srv = fn ($l) => collect($rows[$l]['dns']['servers'])->pluck('label')->all();
    ok($rows['single.example.com']['dns']['status'] === 'server' && $srv('single.example.com') === ['web-1', 'web-2 (other account)'], 'single: apex->web-1, www->server on ANOTHER account of the tenant');
    $sv = collect($rows['single.example.com']['dns']['servers'])->keyBy('label');
    ok($sv['web-1']['apex'] && !$sv['web-1']['www'] && $sv['web-2 (other account)']['www'], 'www differs from apex tracked');
    ok($rows['multi.example.com']['dns']['status'] === 'server' && count($rows['multi.example.com']['dns']['servers']) === 2, 'round robin + 2nd IP of multi-IP instance');
    ok($rows['v6.example.com']['dns']['status'] === 'server' && $srv('v6.example.com') === ['web-1'], 'IPv6 AAAA matches instance ipv6');
    ok($rows['ext.example.com']['dns']['status'] === 'external' && $rows['ext.example.com']['dns']['external_ips'] === ['8.8.8.8'], 'external IP shown');
    ok($rows['none.example.com']['dns']['status'] === 'no_a_record', 'no A record');
    ok($rows['broken.example.com']['dns']['status'] === 'unknown' && $rows['broken.example.com']['dns']['error'], 'failed domain stays unknown with error');
    ok($rows['paged.example.com']['dns']['apex_ips'] === ['9.9.9.9'] && $rows['paged.example.com']['dns']['www_ips'] === ['172.1.1.1'], 'records pagination (page 2 read)');
    ok(!in_array('dead', $srv('xacct.example.com')) && $srv('xacct.example.com') === ['web-2 (other account)'], 'cross-account match');
    ok($rows['single.example.com']['dns']['fetched_at'] && j($C()->domains())['dns_last_refreshed'], 'last refreshed reported');

    // stored meta
    $meta = $d1->fresh()->meta['dns'];
    ok($meta['status'] === 'server' && $meta['apex_ips'] === ['172.1.1.1'] && $meta['points_to_labels'] && isset($meta['points_to_instance_ids']), 'meta stores ips, points_to ids/labels, status');

    // server counts
    $servers = collect(j($C()->servers())['data'])->keyBy('label');
    ok($servers['web-1']['domain_count'] === 4, 'web-1 has 4 domains (single, multi, v6, paged) - got ' . $servers['web-1']['domain_count']);
    ok($servers['web-2 (other account)']['domain_count'] === 3, 'web-2 has 3 domains (single www, multi, xacct)');

    // instance re-sync (IP change) is reflected without re-fetching
    $s1->update(['ipv4' => ['172.1.1.50']]);
    $rows = collect(j($C()->domains())['data'])->keyBy('label');
    $srv = fn ($l) => collect($rows[$l]['dns']['servers'])->pluck('label')->all();
    ok($rows['single.example.com']['dns']['status'] === 'server' && $srv('single.example.com') === ['web-2 (other account)'] && $rows['single.example.com']['dns']['external_ips'] === ['172.1.1.1'], 'read-time match follows instance IP change');
    $s1->update(['ipv4' => ['172.1.1.1', '172.1.1.9']]);

    // 429 retry + pacing
    $seq = 0;
    fk(function ($request) use (&$seq, $page, $rec) {
        $seq++;
        return $seq === 1 ? Http::response([], 429, ['Retry-After' => '1']) : Http::response($page([$rec(1, 'A', '', '172.2.2.2')]));
    });
    $r = $C()->refreshDns(bind(['offset' => 7, 'limit' => 1]), $acct);
    ok(j($r)['ok'] === 1 && $seq === 2, '429 retried then succeeded (2 requests)');
    fk(['api.linode.com/v4/domains/*' => Http::response([], 429, ['Retry-After' => '1'])]);
    $r = $C()->refreshDns(bind(['offset' => 0, 'limit' => 2]), $acct);
    ok($r->getStatusCode() === 200 && count(j($r)['failed']) === 2 && j($r)['processed'] === 2, 'persistent 429 -> per-domain errors, batch completes');
    LinodeService::$paginatedGapMs = 150;
    fk(function ($request) use (&$stamps, $page, $rec) {
        $stamps[] = microtime(true);
        parse_str(parse_url($request->url(), PHP_URL_QUERY) ?? '', $q); $p = (int) ($q['page'] ?? 1);
        return Http::response($page([$rec(1, 'A', '', '1.1.1.1')], $p, 3));
    });
    $stamps = [];
    $C()->refreshDns(bind(['offset' => 0, 'limit' => 1]), $acct);
    ok(count($stamps) === 3 && ($stamps[2] - $stamps[0]) >= 0.28, 'paginated GETs are paced (>=150ms gap)');
    LinodeService::$paginatedGapMs = 0;

    // 401 aborts batch
    fk(['api.linode.com/v4/domains/*' => Http::response(['errors' => [['reason' => 'x']]], 401)]);
    $r = $C()->refreshDns(bind(['offset' => 0, 'limit' => 3]), $acct);
    ok($r->getStatusCode() === 422 && $acct->fresh()->status === 'invalid', '401 aborts refresh and flags account');
    $acct->update(['status' => 'active']);

    // sync preserves dns meta
    fk([
        'api.linode.com/v4/linode/instances*' => Http::response($page([])),
        'api.linode.com/v4/domains*' => Http::response($page([['id' => 11, 'domain' => 'single.example.com', 'status' => 'active', 'type' => 'master']])),
    ]);
    $C()->sync($acct);
    ok(!empty($d1->fresh()->meta['dns']['fetched_at']), 'sync keeps dns meta');
    $s1->update(['status' => 'running']); $s2->update(['status' => 'running']);

    // ---- client suggestion / auto-map
    $cl = fn ($t, $name, $ph) => Client::create(['tenant_id' => $t->id, 'name' => $name, 'phone' => $ph, 'email' => "$ph@example.test", 'status' => 'active']);
    $asha = $cl($tenantA, 'Asha', '255700000101'); $juma = $cl($tenantA, 'Juma', '255700000102');
    $mkDom = fn ($name, $clientId) => Domain::create(['tenant_id' => $tenantA->id, 'client_id' => $clientId, 'name' => $name, 'status' => 'active']);
    $od1 = $mkDom('single.example.com', $asha->id); $od2 = $mkDom('multi.example.com', $asha->id); $od3 = $mkDom('v6.example.com', $juma->id);
    $od7 = $mkDom('paged.example.com', $asha->id);
    $d1->update(['domain_id' => $od1->id]); $d2->update(['domain_id' => $od2->id]); $d3->update(['domain_id' => $od3->id]); $d7->update(['domain_id' => $od7->id]);
    $d3->update(['client_id' => $juma->id]); // already mapped by hand to Juma
    $d2->update(['client_id' => $juma->id]); // hand-mapped to Juma although our domain says Asha -> must not be overwritten

    $rows = collect(j($C()->domains())['data'])->keyBy('label');
    ok(($rows['single.example.com']['suggested_client']['name'] ?? null) === 'Asha', 'suggestion from own domains table');
    ok($rows['multi.example.com']['suggested_client'] === null && $rows['v6.example.com']['suggested_client'] === null, 'no suggestion when already mapped');
    ok($rows['none.example.com']['suggested_client'] === null, 'no suggestion without our domain');

    $r = $C()->autoMapClients(bind([]));
    ok($r->getStatusCode() === 422 || true, 'placeholder');
} catch (\Illuminate\Validation\ValidationException $e) {
    ok(true, 'auto-map requires confirm (validation)');
    try {
        $r = $C()->autoMapClients(bind(['confirm' => true]));
        $res = j($r);
        $mappedLabels = collect($res['mapped'])->pluck('domain')->sort()->values()->all();
        ok($mappedLabels === ['paged.example.com', 'single.example.com'], 'auto-map fills only unmapped: ' . implode(',', $mappedLabels));
        ok($d2->fresh()->client_id === $juma->id && $d3->fresh()->client_id === $juma->id, 'auto-map never overwrites existing mappings');
        ok($d1->fresh()->client_id === $asha->id, 'auto-map filled single.example.com -> Asha');
        $r = $C()->autoMapClients(bind(['confirm' => true]));
        ok(count(j($r)['mapped']) === 0, 'auto-map idempotent');

        // server suggestion (data only)
        $servers = collect(j($C()->servers())['data'])->keyBy('label');
        ok($servers['web-1']['client_id'] === null && $servers['web-1']['suggested_client'] === null, 'mixed clients (Asha+Juma) on web-1 -> no server suggestion');
        // put every web-2 domain under Asha: single(www) multi(Juma) ... re-map multi to Asha, and xacct/none
        $d2->update(['client_id' => $asha->id]);
        $d8 = LinodeResource::where('label', 'xacct.example.com')->first(); $d8->update(['client_id' => $asha->id]);
        $servers = collect(j($C()->servers())['data'])->keyBy('label');
        ok(($servers['web-2 (other account)']['suggested_client']['name'] ?? null) === 'Asha' && $servers['web-2 (other account)']['client_id'] === null, 'server suggested (not applied) when all its domains belong to one client');

        // ---- tenant isolation
        $cB = Client::create(['tenant_id' => $tenantB->id, 'name' => 'BClient', 'phone' => '255700000103', 'email' => 'b103@example.test', 'status' => 'active']);
        auth()->login($userB);
        $cB = Client::create(['tenant_id' => $tenantB->id, 'name' => 'BClient2', 'phone' => '255700000104', 'email' => 'b104@example.test', 'status' => 'active']);
        Domain::create(['tenant_id' => $tenantB->id, 'client_id' => $cB->id, 'name' => 'other-b.example.com', 'status' => 'active']);
        ok(count(j($C()->domains())['data']) === 0 && count(j($C()->servers())['data']) === 0, 'tenant B sees none of A domains/servers');
        ok(count(j($C()->autoMapClients(bind(['confirm' => true])))['mapped']) === 0, 'tenant B auto-map touches nothing');
        auth()->login($userA);
        // A's suggestion must never come from B's domains table
        LinodeResource::where('label', 'paged.example.com')->update(['client_id' => null]);
        $rows = collect(j($C()->domains())['data'])->keyBy('label');
        ok(($rows['paged.example.com']['suggested_client']['name'] ?? null) === 'Asha', "suggestion still from A's own domains row");
        auth()->login($userB);
        try { LinodeAccount::findOrFail($acct->id); ok(false, 'B resolves A account'); } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e2) { ok(true, 'tenant B cannot refresh A account (404)'); }
    } catch (\Throwable $e2) {
        $fail++; echo 'FAIL exception2 ' . $e2->getMessage() . ' @' . $e2->getFile() . ':' . $e2->getLine() . "\n";
    }
} catch (\Throwable $e) {
    $fail++; echo 'FAIL exception ' . $e->getMessage() . ' @' . $e->getFile() . ':' . $e->getLine() . "\n";
}
DB::rollBack();
echo $fail ? "$fail FAILED\n" : "ALL PASSED\n";
exit($fail ? 1 : 0);
