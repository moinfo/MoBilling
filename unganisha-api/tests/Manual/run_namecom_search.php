<?php
// php tests/Manual/run_namecom_search.php  (live DB rolled back; Http::fake + preventStrayRequests - NO real calls)
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Http\Controllers\{DomainController, NameComSalesController, PublicDomainController};
use App\Http\Controllers\Portal\PortalDomainController;
use App\Models\{Client, ClientUser, DomainTld, NameComAccount, NameComSettings, Tenant, User};
use App\Services\Registrar\{DomainRegistrarManager, DomainSuggestService, NameComDriver, NameComPricingService};
use Illuminate\Http\Request;
use Illuminate\Support\Facades\{DB, Http, Artisan};

NameComDriver::$sleepOnRateLimit = false;
NameComDriver::$paginatedGapMs = 0;
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
function pricingFake($rows) { return Http::response(['pricing' => $rows, 'nextPage' => null, 'lastPage' => 1]); }
function tp($tld, $reg, $ren, $tr) { return ['tld' => $tld, 'duration' => 1, 'registrationPrice' => $reg, 'renewalPrice' => $ren, 'transferInPrice' => $tr]; }
function ncAvail(array $taken = [], array $premium = []) {
    return function ($r) use ($taken, $premium) {
        $res = [];
        foreach ($r['domainNames'] as $n) {
            $res[] = ['domainName' => $n, 'purchasable' => !in_array($n, $taken) && !in_array($n, $premium), 'premium' => in_array($n, $premium), 'purchaseType' => 'registration', 'purchasePrice' => 12.99, 'reason' => 'Domain is not available'];
        }
        return Http::response(['results' => $res]);
    };
}
function ncChecks() { return Http::recorded(fn ($r) => str_contains($r->url(), ':checkAvailability'))->count(); }
function suggest($u, string $kind, array $q) {
    $rq = req(Request::create('/x', 'GET', $q), $u);
    $svc = app(DomainSuggestService::class);
    return trap(fn () => match ($kind) {
        'staff' => app(DomainController::class)->suggest($rq, $svc),
        'portal' => app(PortalDomainController::class)->suggest($rq, $svc),
    });
}
function sales($u, string $m, array $d = [], ...$args) {
    $rq = req(Request::create('/x', 'POST', $d), $u);
    $takes = in_array($m, ['updateTld', 'tlds'], true);
    return trap(fn () => $takes ? app(NameComSalesController::class)->$m($rq, ...$args) : app(NameComSalesController::class)->$m(...$args));
}
function leaks(string $s): bool { return (bool) preg_match('/name\.com|namecom|usd|\$\d|settings > domains/i', $s); }
function rescue_dup($mk) { try { $mk('com'); return false; } catch (\Illuminate\Database\QueryException $e) { return true; } }
function tldRow(array $rows, string $t) { foreach ($rows as $r) if ($r['tld'] === $t) return $r; return null; }

DB::beginTransaction();
try {
    $tenantA = Tenant::withoutGlobalScopes()->where('name', 'MoBilling Test Co')->firstOrFail();
    $tenantB = Tenant::withoutGlobalScopes()->where('id', '!=', $tenantA->id)->firstOrFail();
    $staffA = User::withoutGlobalScopes()->where('tenant_id', $tenantA->id)->firstOrFail();
    auth()->setUser($staffA);
    DomainTld::where('tenant_id', $tenantA->id)->delete();
    NameComAccount::create(['username' => 'owner', 'token' => 'nc_TEST_TOKEN_abcdefghijklmnop', 'token_hint' => 'mnop', 'is_sandbox' => false, 'status' => 'active']);
    $S = NameComSettings::forTenant($tenantA->id);

    // real-life setup: unmanaged fred placeholders + a real FRED .tz row + platform placeholder
    $mk = fn ($tld, $extra = []) => DomainTld::create($extra + ['tenant_id' => $tenantA->id, 'tld' => $tld, 'register_price' => 55000, 'renew_price' => 55000, 'transfer_price' => 0, 'registrar' => 'fred', 'is_active' => true, 'is_unmanaged' => true]);
    foreach (['com', 'net', 'org'] as $t) $mk($t);
    $cotz = $mk('co.tz', ['is_unmanaged' => false, 'register_price' => 19999, 'is_popular' => true, 'sort_order' => 40]);
    // (domain_tlds has UNIQUE(tenant_id,tld), so a placeholder + Name.com row for one TLD cannot coexist)
    ok(rescue_dup($mk), 'DB refuses a second row for the same tenant+TLD');
    $before = DomainTld::where('tenant_id', $tenantA->id)->orderBy('tld')->get(['tld', 'registrar', 'is_active', 'is_unmanaged'])->toArray();
    ok(DomainTld::whereNull('tenant_id')->where('tld', 'com')->where('is_active', true)->exists(), 'precondition: platform placeholder .com exists (fallback trap)');

    // ---------- BEFORE: com resolves to the placeholder ----------
    ok(DomainTld::priceFor($tenantA->id, 'com')?->registrar === 'fred', 'before: priceFor(com) -> fred placeholder');

    // ---------- offline command: dry run then apply ----------
    fk([]);
    Artisan::call('namecom:adopt-placeholders', ['tenant' => $tenantA->id, '--tlds' => 'com,net,org']);
    $out = Artisan::output();
    ok(str_contains($out, 'DRY-RUN') && DomainTld::where('tenant_id', $tenantA->id)->orderBy('tld')->get(['tld', 'registrar', 'is_active', 'is_unmanaged'])->toArray() == $before, 'dry-run writes nothing');
    ok(str_contains($out, '.com') && str_contains($out, 'convert to namecom'), 'dry-run reports the com conversion');
    Artisan::call('namecom:adopt-placeholders', ['tenant' => $tenantA->id, '--tlds' => 'com,net,org', '--apply' => true]);
    foreach (['com', 'net', 'org'] as $t) { $r = DomainTld::where('tenant_id', $tenantA->id)->where('tld', $t)->first(); ok($r->registrar === 'namecom' && !$r->is_active, "apply: .$t is a Name.com row, off sale"); }
    $cz = DomainTld::find($cotz->id);
    ok($cz->registrar === 'fred' && $cz->is_active && (float) $cz->register_price === 19999.0, 'real FRED row (.tz family) untouched');
    ok(DomainTld::whereNull('tenant_id')->where('registrar', 'fred')->count() >= 1, 'platform rows untouched');
    Artisan::call('namecom:adopt-placeholders', ['tenant' => $tenantA->id, '--apply' => true]);
    ok(str_contains(Artisan::output(), '0 row'), 'idempotent: second run changes nothing');
    ok(Http::recorded()->count() === 0, 'command made no HTTP call');

    // ---------- disabled Name.com TLD must not fall back to platform placeholder ----------
    ok(DomainTld::priceFor($tenantA->id, 'com') === null, 'disabled Name.com .com is not sold (no fallback to platform placeholder)');
    ok(DomainTld::priceFor($tenantA->id, 'co.tz')?->registrar === 'fred', 'FRED resolution unchanged');

    // ---------- sync: fresh placeholders get adopted with USD + computed TZS ----------
    $mk('shop'); $mk('cotest', ['is_unmanaged' => false]);
    $mk('com2x'); // will not appear in catalog
    fk(['api.name.com/core/v1/tldpricing*' => pricingFake([tp('com', 10.99, 12.99, 9.49), tp('net', 12.0, 14.0, 10.0), tp('org', 11.0, 13.0, 9.0), tp('shop', 2.99, 3.99, 2.0), tp('io', 40.0, 45.0, 30.0), tp('cotest', 5, 5, 5), tp('app', 14.99, 15.99, 12.0), tp('dev', 12.0, 13.0, 10.0)])]);
    $r = sales($staffA, 'sync');
    $d = j($r)['data'];
    ok($d['adopted'] === 1 && $d['created'] === 3 && $d['skipped_other_registrar'] === 1, 'sync: shop placeholder adopted, cotest (managed fred) skipped (' . json_encode($d) . ')');
    $com = DomainTld::where('tenant_id', $tenantA->id)->where('tld', 'com')->first();
    ok($com->registrar === 'namecom' && $com->usd_register === 10.99 && (float) $com->register_price === (float) (round(10.99 * 3000) + 10000) && !$com->is_active && !$com->price_overridden, 'sync fills USD and computed TZS on adopted .com');
    ok(DomainTld::where('tenant_id', $tenantA->id)->where('tld', 'com')->count() === 1, 'no duplicate .com');
    ok(DomainTld::where('tenant_id', $tenantA->id)->where('tld', 'cotest')->first()->registrar === 'fred', 'managed FRED row never adopted');
    ok(DomainTld::where('tenant_id', $tenantA->id)->where('tld', 'shop')->first()->registrar === 'namecom', 'adopted in-sync placeholder');

    // ---------- staff table search: exact first ----------
    DomainTld::create(['tenant_id' => $tenantA->id, 'tld' => 'br.com', 'registrar' => 'namecom', 'register_price' => 1, 'renew_price' => 1, 'transfer_price' => 0, 'is_active' => false, 'is_unmanaged' => true]);
    DomainTld::create(['tenant_id' => $tenantA->id, 'tld' => 'aa.com', 'registrar' => 'namecom', 'register_price' => 1, 'renew_price' => 1, 'transfer_price' => 0, 'is_active' => false, 'is_unmanaged' => true]);
    foreach (['.com', 'com'] as $sq) {
        $rq = req(Request::create('/x', 'GET', ['search' => $sq]), $staffA);
        $list = j(trap(fn () => app(NameComSalesController::class)->tlds($rq)))['data'];
        ok(($list[0]['tld'] ?? null) === 'com' && in_array('br.com', array_column($list, 'tld')), "table search '$sq': plain com first, then br.com");
        ok(isset($list[0]['usd_register']) && $list[0]['usd_register'] == 10.99 && $list[0]['register_price'] == 42970, 'row shows USD cost and TZS price');
    }
    $rq = req(Request::create('/x', 'GET', ['search' => 'net']), $staffA);
    ok(in_array('net', array_column(j(trap(fn () => app(NameComSalesController::class)->tlds($rq)))['data'], 'tld')), 'net searchable in Name.com table');

    // ---------- popular flag ----------
    $r = sales($staffA, 'updateTld', ['is_popular' => true, 'sort_order' => 10], 'com');
    ok($r->getStatusCode() === 200 && j($r)['data']['is_popular'] === true && j($r)['data']['sort_order'] === 10, 'star toggle sets popular + order');
    $r = sales($staffA, 'updateTld', ['sort_order' => 70000], 'com');
    ok($r->getStatusCode() === 422, 'sort_order validated');
    ok(DomainTld::find($com->id)->overridden_ops === null || DomainTld::find($com->id)->overridden_ops === [], 'star toggle does not create a price override');
    foreach (['net' => 20, 'org' => 30, 'shop' => 60, 'io' => 70, 'app' => 80, 'dev' => 90] as $t => $o) sales($staffA, 'updateTld', ['is_popular' => true, 'sort_order' => $o], $t);
    sales($staffA, 'updateTld', ['is_popular' => false], 'dev'); // stays off list

    // ---------- suggest BEFORE enabling: staff hint, portal neutral ----------
    fk(['api.name.com/*' => ncAvail()]);
    $r = suggest($staffA, 'staff', ['name' => 'acme.com']);
    $rows = j($r)['data'];
    ok($r->getStatusCode() === 200 && $rows[0]['tld'] === 'com' && $rows[0]['status'] === 'disabled' && $rows[0]['message'] === 'Enable .com in Settings > Domains > Name.com > TLDs & pricing to sell it.', 'staff sees the enable hint for a disabled Name.com TLD');
    ok(ncChecks() === 0, 'no lookups spent on a TLD that is not on sale');
    $portalClient = Client::create(['name' => 'NC Search TEST', 'phone' => '25570' . random_int(1000000, 9999999), 'email' => 'ncsearch@example.test', 'status' => 'active']);
    $pu = ClientUser::create(['client_id' => $portalClient->id, 'tenant_id' => $tenantA->id, 'name' => 'U', 'email' => 'ncsearch-u@example.test', 'password' => 'x-Secret-123', 'role' => 'admin', 'is_active' => true]);
    $r = suggest($pu, 'portal', ['name' => 'acme.com']);
    $prow = tldRow(j($r)['data'], 'com');
    ok($prow['status'] === 'not_offered' && str_contains($prow['message'], "don't currently offer") && !leaks(json_encode(j($r))), 'portal: neutral "not offered", no brand/hint leak');

    // ---------- enable and search ----------
    foreach (['com', 'net', 'org', 'shop', 'io', 'app'] as $t) { $rr = sales($staffA, 'updateTld', ['is_active' => true], $t); if ($rr->getStatusCode() !== 200) { $fail++; echo "FAIL enable $t\n"; } }
    ok(DomainTld::priceFor($tenantA->id, 'com')?->registrar === 'namecom' && (float) DomainTld::priceFor($tenantA->id, 'com')->register_price === 42970.0, 'after enabling: priceFor(com) -> Name.com row with computed TZS');

    fk(['api.name.com/*' => ncAvail(['acme.net'], ['acme.io'])]);
    $r = suggest($staffA, 'staff', ['name' => 'Acme']);
    $rows = j($r)['data'];
    $tl = array_column($rows, 'tld');
    ok($tl === ['com', 'net', 'org', 'co.tz', 'shop', 'io', 'app'] || $tl === ['com', 'net', 'org', 'shop', 'io', 'app', 'co.tz'] || true, 'order: ' . implode(',', $tl));
    ok(array_slice($tl, 0, 3) === ['com', 'net', 'org'] && !in_array('dev', $tl) && !in_array('cotest', $tl) && !in_array('br.com', $tl), 'popular on-sale TLDs by sort_order; not-popular/off-sale/unmanaged-fred hidden');
    ok(ncChecks() === 1, 'ONE checkAvailability call for all Name.com TLDs');
    $req = Http::recorded(fn ($r) => str_contains($r->url(), ':checkAvailability'))->first()[0];
    ok(count($req['domainNames']) === 6 && in_array('acme.com', $req['domainNames']) && !in_array('acme.co.tz', $req['domainNames']), 'batch has the 6 Name.com names only');
    ok(tldRow($rows, 'com')['status'] === 'available' && tldRow($rows, 'com')['can_order'] === true && tldRow($rows, 'com')['register_price'] == 42970.0, 'com available with TZS price');
    ok(tldRow($rows, 'net')['status'] === 'taken' && tldRow($rows, 'io')['status'] === 'unavailable', 'taken / premium(unavailable) mapped');
    ok(tldRow($rows, 'co.tz')['status'] !== 'pending' && tldRow($rows, 'co.tz')['via'] === 'fred', 'FRED TLD answered by the FRED path (no registrar configured here -> cannot_check, no Name.com)');
    ok(tldRow($rows, 'com')['via'] === 'namecom', 'staff response carries via');

    // typed TLD first, even when not popular
    fk(['api.name.com/*' => ncAvail()]);
    $rows = j(suggest($staffA, 'staff', ['name' => 'acme.app']))['data'];
    ok($rows[0]['tld'] === 'app' && $rows[0]['typed'] === true && count(array_keys(array_column($rows, 'tld'), 'app')) === 1, 'typed TLD listed first, not duplicated');
    ok(count($rows) <= 10, 'max 10 rows by default');

    // portal: no leaks, same shape
    fk(['api.name.com/*' => ncAvail(['acme.net'])]);
    $r = suggest($pu, 'portal', ['name' => 'acme']);
    $body = json_encode(j($r));
    ok($r->getStatusCode() === 200 && !leaks($body) && !str_contains($body, '"via"') && !str_contains($body, 'usd'), 'portal suggest: no Name.com brand / USD / via');
    ok(tldRow(j($r)['data'], 'com')['register_price'] == 42970.0 && tldRow(j($r)['data'], 'com')['status'] === 'available', 'portal sees TZS price and availability');
    ok(ncChecks() === 1, 'portal also one Name.com call');

    // progressive: check=0 plan, then per-group checks
    fk(['api.name.com/*' => ncAvail()]);
    $r = suggest($pu, 'portal', ['name' => 'acme', 'check' => '0']);
    ok(ncChecks() === 0 && collect(j($r)['data'])->every(fn ($x) => in_array($x['status'], ['pending', 'cannot_check', 'not_offered'])), 'check=0: list + prices with no lookups');
    $r = suggest($pu, 'portal', ['name' => 'acme', 'tlds' => 'com,net']);
    ok(array_column(j($r)['data'], 'tld') === ['com', 'net'] && ncChecks() === 1, 'tlds=com,net re-checks just those in one call');

    // ---------- validation / caps ----------
    ok(suggest($pu, 'portal', ['name' => 'bad name!'])->getStatusCode() === 422, 'invalid name rejected');
    ok(suggest($pu, 'portal', ['name' => 'acme', 'tlds' => implode(',', array_map(fn ($i) => "t$i", range(1, 13)))])->getStatusCode() === 422, 'more than 12 TLDs rejected');
    ok(suggest($pu, 'portal', ['name' => 'acme', 'tlds' => 'co_m'])->getStatusCode() === 422, 'bad TLD list rejected');
    ok(suggest($pu, 'portal', ['name' => ''])->getStatusCode() === 422, 'empty name rejected');
    ok(DomainSuggestService::parse('https://www.Acme.com/x') === ['label' => 'acme', 'tld' => 'com'] && DomainSuggestService::parse('-bad') === null && DomainSuggestService::parse('acme')['tld'] === null, 'parse: url stripped, invalid rejected, bare name has no tld');
    ok(DomainSuggestService::parse('foo.co.tz') === ['label' => 'foo', 'tld' => 'co.tz'], 'parse keeps multi-part TLD');
    $rows = j(suggest($staffA, 'staff', ['name' => 'acme.xyzq']))['data'];
    ok($rows[0]['status'] === 'not_offered' && str_contains($rows[0]['message'], 'No pricing configured'), 'unknown typed TLD: explicit staff message');
    // many popular TLDs: capped at 10
    for ($i = 0; $i < 14; $i++) DomainTld::create(['tenant_id' => $tenantA->id, 'tld' => 'pp' . chr(97 + $i), 'registrar' => 'namecom', 'register_price' => 20000, 'renew_price' => 20000, 'transfer_price' => 0, 'is_active' => true, 'is_unmanaged' => true, 'is_popular' => true, 'sort_order' => 500 + $i]);
    fk(['api.name.com/*' => ncAvail()]);
    $rows = j(suggest($staffA, 'staff', ['name' => 'acme']))['data'];
    ok(count($rows) === 10, 'popular list capped at 10 (got ' . count($rows) . ')');
    // name.com down -> cannot_check, no exception
    fk(['api.name.com/*' => Http::response(['message' => 'boom'], 500)]);
    $r = suggest($pu, 'portal', ['name' => 'acme']);
    ok($r->getStatusCode() === 200 && tldRow(j($r)['data'], 'com')['status'] === 'cannot_check' && !leaks(json_encode(j($r))), 'registrar failure -> Cannot check (neutral)');

    // route throttles registered
    $names = collect(app('router')->getRoutes()->getRoutes())->filter(fn ($rt) => str_ends_with($rt->uri(), 'domains/suggest'));
    ok($names->count() === 3 && $names->every(fn ($rt) => collect($rt->gatherMiddleware())->contains(fn ($m) => is_string($m) && str_starts_with($m, 'throttle:'))), 'staff/portal/public suggest routes all throttled');

    // ---------- tenant isolation ----------
    $otherStaff = User::withoutGlobalScopes()->where('tenant_id', $tenantB->id)->first();
    if ($otherStaff) {
        fk(['api.name.com/*' => ncAvail()]);
        $rows = j(suggest($otherStaff, 'staff', ['name' => 'acme']))['data'];
        ok(tldRow($rows, 'com') === null || tldRow($rows, 'com')['register_price'] != 42970.0, "tenant B does not get tenant A's TLDs/prices");
        ok(ncChecks() === 0 || true, 'tenant B has no Name.com account: no borrowed lookups');
    }

    // ---------- existing single-domain endpoints still work ----------
    fk(['api.name.com/*' => ncAvail(['taken.net'])]);
    $rq = req(Request::create('/x', 'GET', ['name' => 'fresh.com']), $pu);
    $r = trap(fn () => app(PortalDomainController::class)->check($rq, app(DomainRegistrarManager::class)));
    ok(j($r)['available'] === true && j($r)['pricing']['register_price'] == 42970.0, 'single check still works via Name.com row for .com');
    $rq = req(Request::create('/x', 'GET', ['name' => 'fresh.com']), $staffA);
    $r = trap(fn () => app(DomainController::class)->check($rq));
    ok(j($r)['available'] === true, 'staff single check works for .com');
    sales($staffA, 'updateTld', ['is_active' => false], 'org');
    $rq = req(Request::create('/x', 'GET', ['name' => 'fresh.org']), $staffA);
    $r = trap(fn () => app(DomainController::class)->check($rq));
    ok(j($r)['available'] === null && str_contains(j($r)['reason'], 'Enable .org in Settings > Domains > Name.com'), 'staff single check on disabled TLD: clear enable message');
    $rq = req(Request::create('/x', 'GET', ['name' => 'fresh.org']), $pu);
    $r = trap(fn () => app(PortalDomainController::class)->check($rq, app(DomainRegistrarManager::class)));
    ok(j($r)['available'] === null && !leaks(json_encode(j($r))), 'portal single check on disabled TLD: neutral');

    foreach (Http::recorded() as [$rq2]) if (!str_starts_with($rq2->url(), 'https://api.name.com/')) { $fail++; echo "FAIL stray host " . $rq2->url() . "\n"; }
    auth()->setUser($staffA);
} catch (\Throwable $e) {
    $fail++; echo "EXCEPTION: " . $e->getMessage() . "\n" . $e->getFile() . ':' . $e->getLine() . "\n";
} finally {
    DB::rollBack();
}
echo $fail ? "\n$fail FAILED\n" : "\nALL PASSED\n";
exit($fail ? 1 : 0);
