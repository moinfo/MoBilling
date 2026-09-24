<?php
// php tests/Manual/run_namecom_sales.php  (live DB rolled back; Name.com fully faked, Http::preventStrayRequests - NO real calls)
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Exceptions\NameComApiException;
use App\Http\Controllers\{DomainController, NameComSalesController, PublicDomainController};
use App\Http\Controllers\Portal\{PortalDomainController, PortalOrderController};
use App\Http\Middleware\CheckPermission;
use App\Jobs\Domains\AutoRegisterNameComDomainJob;
use App\Models\{Client, ClientUser, Document, Domain, DomainLog, DomainTld, NameComAccount, NameComAuditLog, NameComSettings, Tenant, User};
use App\Notifications\{DomainReadyNotification, NameComRegistrationPendingNotification};
use App\Services\Registrar\{DomainBillingService, DomainRegistrarManager, NameComDriver, NameComPricingService, NameComRegistrationService};
use Illuminate\Http\Request;
use Illuminate\Support\Facades\{Bus, DB, Http, Notification};

NameComDriver::$sleepOnRateLimit = false;
NameComDriver::$paginatedGapMs = 0;
$fail = 0;
function ok($c, $m) { global $fail; if (!$c) { $fail++; echo "FAIL $m\n"; } else echo "PASS $m\n"; }
function fk($x) { Http::swap(new \Illuminate\Http\Client\Factory()); Http::preventStrayRequests(); Http::fake($x); }
function j($r) { return $r->getData(true); }
function posts() { return Http::recorded(fn ($r) => $r->method() === 'POST')->count(); }
function creates() { return Http::recorded(fn ($r) => $r->method() === 'POST' && $r->url() === 'https://api.name.com/core/v1/domains')->count(); }
function hits() { return Http::recorded()->count(); }
function req(Request $rq, $u) { $rq->setUserResolver(fn () => $u); app()->instance('request', $rq); auth()->setUser($u); return $rq; }
function trap(callable $f) {
    try { return $f(); }
    catch (\Symfony\Component\HttpKernel\Exception\HttpException $e) { return response()->json(['message' => $e->getMessage()], $e->getStatusCode()); }
    catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) { return response()->json(['message' => 'not found'], 404); }
    catch (\Illuminate\Validation\ValidationException $e) { return response()->json(['message' => $e->getMessage()], 422); }
}
function sales($u, string $m, array $d = [], ...$args) {
    $rq = req(Request::create('/x', 'POST', $d), $u);
    $takesReq = in_array($m, ['saveSettings', 'updateTld', 'ackChanges', 'register', 'tlds'], true);
    return trap(fn () => $takesReq ? app(NameComSalesController::class)->$m($rq, ...$args) : app(NameComSalesController::class)->$m(...$args));
}
function pcheck(ClientUser $u, string $name) { $rq = req(Request::create('/x', 'GET', ['name' => $name]), $u); return trap(fn () => app(PortalDomainController::class)->check($rq, app(DomainRegistrarManager::class))); }
function porder(ClientUser $u, array $d) { $rq = req(Request::create('/x', 'POST', $d), $u); return trap(fn () => app(PortalDomainController::class)->order($rq, app(DomainRegistrarManager::class))); }
function pdom(ClientUser $u, string $m, Domain $dom) { $rq = req(Request::create('/x', 'GET'), $u); return trap(fn () => app(PortalDomainController::class)->$m($rq, $dom)); }
function sentTo($u, string $cls): int { return Notification::sent($u, $cls)->count(); }
function leaks(string $s): bool { return (bool) preg_match('/name\.com|namecom|10\.99|21\.98|12\.99|usd|\$\d/i', $s); }
function pricing(array $rows, ?int $next = null) { return Http::response(['pricing' => $rows, 'nextPage' => $next, 'lastPage' => $next ?? 1, 'totalCount' => count($rows)]); }
function tp($tld, $reg, $ren, $tr) { return ['tld' => $tld, 'duration' => 1, 'registrationPrice' => $reg, 'renewalPrice' => $ren, 'transferInPrice' => $tr]; }
/** Full fake for a registration scenario. */
function nc(array $o = []) {
    $o += ['avail' => true, 'premium' => false, 'live' => 21.98, 'create' => null, 'domain' => null];
    return [
        'api.name.com/core/v1/domains:checkAvailability' => function ($r) use ($o) {
            $n = $r['domainNames'][0];
            return Http::response(['results' => [['domainName' => $n, 'sld' => 'x', 'tld' => 'y', 'purchasable' => $o['avail'], 'premium' => $o['premium'], 'purchaseType' => 'registration', 'purchasePrice' => 10.99, 'renewalPrice' => 12.99]]]);
        },
        'api.name.com/core/v1/tldpricing*' => Http::response(['pricing' => [['tld' => 'nctesta', 'duration' => 2, 'registrationPrice' => $o['live']]]]),
        'api.name.com/core/v1/domains' => $o['create'] ?? function ($r) {
            $n = $r['domain']['domainName'];
            return Http::response(['domain' => ['domainName' => $n, 'createDate' => '2026-09-27T10:00:00Z', 'expireDate' => '2028-09-27T10:00:00Z', 'locked' => true, 'autorenewEnabled' => false, 'nameservers' => ['ns1.name.com', 'ns2.name.com']], 'order' => 4242, 'totalPaid' => 21.98]);
        },
        'api.name.com/core/v1/domains/*' => $o['domain'] ?? Http::response(['message' => 'Not Found'], 404),
    ];
}
function mkClient(string $tag, array $extra = []) {
    return Client::create(array_merge(['name' => "NC Sales $tag TEST", 'phone' => '25570' . random_int(1000000, 9999999), 'email' => "ncs-$tag@example.test", 'status' => 'active'], $extra));
}
$fullAddr = ['first_name' => 'Asha', 'last_name' => 'Mushi', 'address_1' => 'Plot 5 Samora Ave', 'city' => 'Dar es Salaam', 'state' => 'Dar es Salaam', 'postcode' => '11101', 'country' => 'TZ'];

DB::beginTransaction();
try {
    $tenantA = Tenant::withoutGlobalScopes()->where('name', 'MoBilling Test Co')->firstOrFail();
    $tenantB = Tenant::withoutGlobalScopes()->where('id', '!=', $tenantA->id)->whereHas('users')->first() ?? Tenant::withoutGlobalScopes()->where('id', '!=', $tenantA->id)->firstOrFail();
    $staffA = User::withoutGlobalScopes()->where('tenant_id', $tenantA->id)->firstOrFail();
    auth()->setUser($staffA);
    $account = NameComAccount::create(['username' => 'owner', 'token' => 'nc_TEST_TOKEN_abcdefghijklmnop', 'token_hint' => 'mnop', 'is_sandbox' => false, 'status' => 'active']);

    // ---------- pricing formula ----------
    $S = NameComSettings::forTenant($tenantA->id);
    ok($S->usd_rate == 3000 && $S->fixed_markup == 10000 && $S->auto_register === false && $S->auto_cap_usd == 50 && $S->auto_daily_limit == 10, 'defaults: rate 3000, markup 10000, auto OFF, cap $50, 10/day');
    ok(NameComPricingService::sellingPrice(10.99, $S) === (float) (round(10.99 * 3000) + 10000) && NameComPricingService::sellingPrice(10.99, $S) === 42970.0, '$10.99 -> round(10.99*3000)+10000 = 42970');
    $pp = NameComPricingService::pricesFor(10.99, 12.99, 9.49, $S);
    ok($pp['register'] === 42970.0 && $pp['renew'] === 48970.0 && $pp['transfer'] === 38470.0, 'register/renew/transfer priced separately (each usd*rate+markup)');
    ok(NameComPricingService::pricesFor(null, 1.0, null, $S)['register'] === null, 'null USD (unsupported op) stays null');
    ok(NameComPricingService::sellingPrice(0.995, $S) === 12985.0, 'rounded to whole TZS (0.995*3000=2985 +10000)');

    // ---------- sync ----------
    $tdA = 'nctesta'; $tdB = 'nctestb'; $tdC = 'nctestc'; $tdD = 'nctestd';
    DomainTld::create(['tenant_id' => $tenantA->id, 'tld' => $tdD, 'register_price' => 5000, 'renew_price' => 6000, 'transfer_price' => 0, 'registrar' => 'fred', 'is_active' => true]);
    $nonNc = fn () => DomainTld::withoutGlobalScopes()->where('registrar', '!=', 'namecom')->orderBy('id')->get()->map->getAttributes()->all();
    $snapshot = $nonNc();
    fk(['api.name.com/core/v1/tldpricing*' => Http::sequence()
        ->push('', 429, ['Retry-After' => '1'])
        ->push(['pricing' => [tp($tdA, 10.99, 12.99, 9.49), tp($tdC, null, 5.0, null), tp('рф', 1, 1, 1)], 'nextPage' => 2, 'lastPage' => 2])
        ->push(['pricing' => [tp($tdB, 1.99, 2.99, 1.49), tp($tdD, 3.0, 3.0, 3.0), tp('xn--p1ai', 1, 1, 1)], 'nextPage' => null, 'lastPage' => 2])]);
    $r = sales($staffA, 'sync');
    $d = j($r)['data'] ?? [];
    ok($r->getStatusCode() === 200 && $d['created'] === 3 && $d['skipped_other_registrar'] === 1 && $d['skipped_invalid'] === 2, 'sync: 3 created, 1 other-registrar skipped, 2 IDN skipped (' . json_encode($d) . ')');
    ok(hits() === 3 && posts() === 0, 'sync: 429 backoff then 2 pages, GET only');
    $q = Http::recorded()->last()[0];
    ok(str_starts_with($q->url(), 'https://api.name.com/core/v1/tldpricing') && str_contains($q->url(), 'duration=1') && $q->method() === 'GET', 'GET /core/v1/tldpricing?duration=1');
    $a = DomainTld::where('tenant_id', $tenantA->id)->where('tld', $tdA)->first();
    ok($a->registrar === 'namecom' && $a->is_active === false && $a->is_unmanaged === true && (float) $a->register_price === 42970.0 && (float) $a->renew_price === 48970.0 && (float) $a->transfer_price === 38470.0 && $a->usd_register === 10.99 && $a->usd_renew === 12.99 && $a->usd_transfer === 9.49, 'new TLD: disabled, unmanaged, raw USD stored, TZS per op');
    $c = DomainTld::where('tenant_id', $tenantA->id)->where('tld', $tdC)->first();
    ok($c->usd_register === null && (float) $c->register_price === 0.0 && !$c->is_active, 'TLD without registration stored with null USD, disabled');
    ok($nonNc() == $snapshot, 'FRED/other-registrar rows (incl. platform + same-tld tenant row) completely untouched');
    ok(DomainTld::where('tenant_id', $tenantA->id)->where('tld', $tdD)->first()->registrar === 'fred', 'conflicting FRED row keeps its registrar');

    // enable + override, then re-sync with changed USD
    $r = sales($staffA, 'updateTld', ['is_active' => true], $tdC);
    ok($r->getStatusCode() === 422, 'cannot enable a TLD without registration support');
    $r = sales($staffA, 'updateTld', ['is_active' => true], $tdA);
    ok($r->getStatusCode() === 200 && $a->fresh()->is_active, 'enable TLD for sale');
    $r = sales($staffA, 'updateTld', ['renew_price' => 60000.4], $tdA);
    ok(j($r)['data']['renew_price'] == 60000 && j($r)['data']['price_overridden'] === true, 'staff override renew price (whole TZS, flagged manual)');
    $r = sales($staffA, 'updateTld', ['is_active' => true, 'register_price' => 0], $tdB);
    ok($r->getStatusCode() === 422, 'cannot enable with zero price');
    fk(['api.name.com/core/v1/tldpricing*' => pricing([tp($tdA, 11.99, 13.99, 9.49), tp($tdB, 2.49, 2.99, 1.49), tp($tdC, null, 5.0, null), tp($tdD, 3.0, 3.0, 3.0)])]);
    $r = sales($staffA, 'sync');
    $d = j($r)['data'];
    ok($d['created'] === 0 && $d['changed'] === 2 && $d['unchanged'] === 1 && $d['skipped_other_registrar'] === 1, 're-sync: 2 changed, 1 unchanged, 0 created (' . json_encode($d) . ')');
    $a = $a->fresh(); $b = DomainTld::where('tenant_id', $tenantA->id)->where('tld', $tdB)->first();
    ok($a->is_active === true, 're-sync keeps enabled flag');
    ok((float) $a->renew_price === 60000.0 && $a->price_overridden === true, 're-sync keeps manual override (renew stays 60000 although USD changed)');
    ok($a->usd_renew === 13.99 && $a->usd_changed === true && $a->usd_prev['renew'] === 12.99, 'price change flagged with previous USD');
    ok((float) $a->register_price === 45970.0 && $a->overridden_ops === ['renew'], 'only the overridden operation (renew) is frozen; register follows the new USD price');
    ok($b->usd_changed && (float) $b->register_price === (float) (round(2.49 * 3000) + 10000) && $b->is_active === false, 'non-overridden row re-priced from new USD, still disabled');
    sales($staffA, 'updateTld', ['is_active' => false], $tdB);
    sales($staffA, 'sync');
    ok(DomainTld::where('tenant_id', $tenantA->id)->where('tld', $tdB)->first()->is_active === false, 're-sync keeps disabled flag');
    $r = sales($staffA, 'ackChanges', ['tlds' => [$tdB]]);
    ok(!$b->fresh()->usd_changed && $a->fresh()->usd_changed, 'acknowledge clears flags selectively');

    // settings + recompute
    $r = sales($staffA, 'saveSettings', ['usd_rate' => 2600, 'fixed_markup' => 5000, 'auto_register' => false, 'auto_cap_usd' => 50, 'auto_daily_limit' => 10]);
    ok($r->getStatusCode() === 200 && NameComSettings::forTenant($tenantA->id)->usd_rate == 2600, 'settings saved per tenant');
    ok((float) $b->fresh()->register_price === (float) (round(2.49 * 3000) + 10000), 'saving settings alone does not re-price');
    $r = sales($staffA, 'recompute');
    ok((float) $b->fresh()->register_price === (float) (round(2.49 * 2600) + 5000) && (float) $a->fresh()->renew_price === 60000.0, 'recompute uses new rate; manual overrides kept');
    ok(NameComAuditLog::where('action', 'settings.update')->exists() && NameComAuditLog::where('action', 'tlds.sync')->exists(), 'settings + sync audited');
    sales($staffA, 'saveSettings', ['usd_rate' => 3000, 'fixed_markup' => 10000, 'auto_register' => false, 'auto_cap_usd' => 50, 'auto_daily_limit' => 10]);
    sales($staffA, 'updateTld', ['reset_override' => true], $tdA);
    ok((float) $a->fresh()->renew_price === (float) (round(13.99 * 3000) + 10000) && !$a->fresh()->price_overridden, 'reset override returns to formula');

    $r = sales($staffA, 'tlds', []);
    $jl = json_encode(j($r));
    ok($r->getStatusCode() === 200 && j($r)['counts']['total'] === 3 && count(j($r)['data']) === 3, 'staff TLD list works (preview table data)');
    ok(str_contains($jl, '"usd_register"'), 'staff list shows USD cost');
    ok(!str_contains(json_encode(DomainTld::where('tld', $tdA)->first()->toArray()), 'usd_'), 'DomainTld serialisation hides USD columns');
    ok(DomainTld::where('tenant_id', $tenantA->id)->where('registrar', 'namecom')->count() === 3, '3 Name.com rows for tenant');
    $legacyIdx = app(\App\Http\Controllers\DomainTldController::class)->index();
    ok(!str_contains(json_encode($legacyIdx->getData(true)), $tdA), 'legacy TLD pricing table does not list Name.com rows');
    $rq = req(Request::create('/x', 'PUT', ['is_active' => false]), $staffA);
    ok(trap(fn () => app(\App\Http\Controllers\DomainTldController::class)->update($rq, $a->fresh()))->getStatusCode() === 422, 'legacy editor refuses Name.com rows');

    // ---------- portal check / order ----------
    $clientA = mkClient('A', $fullAddr);
    $clientB = mkClient('B', $fullAddr);
    $mkUser = fn ($c, $role, $email) => ClientUser::create(['client_id' => $c->id, 'tenant_id' => $tenantA->id, 'name' => 'U ' . $email, 'email' => $email, 'password' => 'x-Secret-123', 'role' => $role, 'is_active' => true]);
    $uA = $mkUser($clientA, 'admin', 'ncs-ua@example.test'); $uB = $mkUser($clientB, 'admin', 'ncs-ub@example.test');
    Notification::fake();

    $name = 'shop-ncs-test.' . $tdA;
    fk(nc());
    $r = pcheck($uA, $name);
    $chk = j($r);
    ok($r->getStatusCode() === 200 && $chk['available'] === true && $chk['pricing']['register_price'] == 45970, 'portal check: available with TZS price (usd 11.99*3000+10000)');
    ok(!leaks(json_encode($chk)), 'portal check response has no USD / Name.com wording');
    $av = Http::recorded()->first()[0];
    ok($av->method() === 'POST' && $av->url() === 'https://api.name.com/core/v1/domains:checkAvailability' && $av->data() === ['domainNames' => [$name], 'purchaseType' => 'registration'] && creates() === 0, 'availability = POST :checkAvailability (read-only) with exact body, no create');
    fk(nc(['avail' => false]));
    ok(j(pcheck($uA, $name))['available'] === false, 'taken domain -> not available');
    fk(nc(['premium' => true]));
    ok(j(pcheck($uA, $name))['available'] === false, 'premium domain -> not sold');
    fk(nc());

    fk(nc());
    $docs0 = Document::count();
    $r = porder($uA, ['name' => $name, 'years' => 2, 'action' => 'register']);
    ok($r->getStatusCode() === 201, 'portal order created (' . ($r->getStatusCode() === 201 ? 'ok' : json_encode(j($r))) . ')');
    $doc = Document::where('client_id', $clientA->id)->orderByDesc('created_at')->first();
    ok($doc && (float) $doc->total === 91940.0 && Document::count() === $docs0 + 1, 'invoice total = 2 x 45970');
    $item = $doc->items()->first();
    ok((float) $item->price === 45970.0 && (int) $item->quantity === 2 && !leaks($item->description . $doc->notes), 'invoice line neutral, unit TZS price');
    $dom = Domain::where('name', $name)->first();
    ok($dom->status === 'pending' && $dom->registrar_account_id === null && $dom->meta['registrar'] === 'namecom' && $dom->meta['unmanaged'] === true && $dom->meta['namecom_years'] === 2 && $dom->meta['pending_action'] === 'register' && $dom->meta['order_document_id'] === $doc->id, 'pending Domain row with order meta, no FRED account');
    ok(!leaks(json_encode(j($r))) && creates() === 0 && posts() === 1, 'order response neutral; order made no create call (only the availability POST)');
    ok(j(porder($uA, ['name' => 'a-ncs-test.' . $tdA, 'years' => 1, 'action' => 'transfer', 'auth_info' => 'x']))['message'] === 'Transfers of .nctesta domains are handled by our team — please contact us.', 'transfer of Name.com TLD refused neutrally');
    fk(nc(['avail' => false]));
    $n0 = Document::count();
    ok(porder($uA, ['name' => 'taken-ncs-test.' . $tdA, 'years' => 1, 'action' => 'register'])->getStatusCode() === 422 && Document::count() === $n0, 'unavailable name: no invoice created');
    ok(porder($uA, ['name' => 'off-ncs-test.' . $tdB, 'years' => 1, 'action' => 'register'])->getStatusCode() === 422, 'disabled TLD cannot be ordered');
    $wiz = json_encode(app(PortalOrderController::class)->tlds(req(Request::create('/x'), $uA))->getData(true));
    ok(!str_contains($wiz, $tdA), 'hosting-wizard TLD list excludes Name.com TLDs');

    // staff order path shares the routing
    fk(nc());
    $rq = req(Request::create('/x', 'POST', ['name' => 'staff-ncs-test.' . $tdA, 'client_id' => $clientB->id, 'years' => 1, 'action' => 'register']), $staffA);
    $r = trap(fn () => app(DomainController::class)->order($rq));
    $sd = Domain::where('name', 'staff-ncs-test.' . $tdA)->first();
    ok($r->getStatusCode() === 201 && $sd && $sd->meta['registrar'] === 'namecom' && $sd->registrar_account_id === null && creates() === 0, 'staff order for Name.com TLD: same pending row, availability via Name.com');

    // ---------- FRED routing untouched ----------
    fk(['api.name.com/*' => Http::response([], 500)]);
    $fredRow = DomainTld::where('tenant_id', $tenantA->id)->where('tld', $tdD)->first();
    try { app(DomainRegistrarManager::class)->checkFor($tenantA->id, 'x.' . $tdD, $fredRow); } catch (\Throwable $e) {}
    ok(Http::recorded(fn ($r) => str_contains($r->url(), 'api.name.com'))->count() === 0, 'non-Name.com TLD never routed to Name.com');

    // ---------- paid order -> manual queue ----------
    Bus::fake();
    $notPaidYet = Domain::where('name', $name)->first();
    fk([]);
    $doc->update(['status' => 'paid']);
    $dom = $dom->fresh();
    ok($dom->status === 'pending' && $dom->meta['awaiting_manual_registration'] === true && !isset($dom->meta['pending_action']) && $dom->meta['namecom_years'] === 2, 'paid -> awaiting_manual_registration, NOT registered');
    ok(hits() === 0, 'paid invoice made no Name.com call (auto OFF)');
    ok(sentTo($staffA, NameComRegistrationPendingNotification::class) === 1, 'staff notified: paid Name.com order waiting for registration');
    ok(Bus::dispatched(AutoRegisterNameComDomainJob::class)->count() === 0 && Bus::dispatched(\App\Jobs\Domains\RegisterDomainJob::class)->count() === 0, 'no auto job and no FRED RegisterDomainJob dispatched');

    // customer sees neutral status only
    $pi = json_encode(j(app(PortalDomainController::class)->index(req(Request::create('/x'), $uA))));
    $ps = json_encode(j(pdom($uA, 'show', $dom)));
    ok(!leaks($pi) && !leaks($ps) && str_contains($pi, '"awaiting_manual_registration":true'), 'portal list/show for queued domain: neutral, no supplier or USD wording');

    // ---------- manual registration ----------
    $poor = mkClient('poor', ['first_name' => 'X', 'phone' => '0712000111']);
    $pd = Domain::create(['client_id' => $poor->id, 'name' => 'poor-ncs-test.' . $tdA, 'status' => 'pending', 'meta' => ['unmanaged' => true, 'registrar' => 'namecom', 'awaiting_manual_registration' => true, 'namecom_years' => 1]]);
    fk(nc(['live' => 11.99]));
    $r = sales($staffA, 'registrationPreview', [], $pd);
    $pv = j($r)['data'];
    ok($pv['can_register'] === false && str_contains(implode(' ', $pv['blockers']), 'missing') && str_contains(implode(' ', $pv['missing']), 'postal code') && str_contains(implode(' ', $pv['missing']), 'last name'), 'missing contact fields listed clearly');
    $r = sales($staffA, 'register', ['confirm' => true, 'usd_cost' => 11.99], $pd);
    ok($r->getStatusCode() === 422 && creates() === 0 && $pd->fresh()->status === 'pending', 'missing fields: refused, no create call');

    // preview for the good domain
    fk(nc());
    $r = sales($staffA, 'registrationPreview', [], $dom);
    $pv = j($r)['data'];
    ok($pv['can_register'] && $pv['years'] === 2 && $pv['usd_cost'] === 21.98 && $pv['invoice_total'] == 91940 && $pv['contact']['country'] === 'TZ', 'preview shows years, USD cost, invoice total and the contact');
    ok($pv['contact']['firstName'] === 'Asha' && $pv['contact']['zip'] === '11101' && creates() === 0, 'contact mapped from client; preview made no create call');
    ok($pv['price_changed'] === false && $pv['usd_expected'] === 23.98, 'expected (synced) price = 11.99 x 2');

    // no / wrong confirmation
    $r = sales($staffA, 'register', ['usd_cost' => 21.98], $dom);
    ok($r->getStatusCode() === 422 && creates() === 0, 'confirm flag required');
    $r = sales($staffA, 'register', ['confirm' => true, 'usd_cost' => 5.00], $dom);
    ok($r->getStatusCode() === 422 && creates() === 0 && str_contains(j($r)['message'], 'changed'), 'stale/incorrect USD confirmation refused, no create');

    // create fails at Name.com (insufficient funds) -> stays queued
    fk(nc(['create' => Http::response(['message' => 'Payment Required', 'details' => 'Insufficient funds'], 402)]));
    $r = sales($staffA, 'register', ['confirm' => true, 'usd_cost' => 21.98], $dom);
    ok($r->getStatusCode() === 422 && $dom->fresh()->status === 'pending' && $dom->fresh()->meta['awaiting_manual_registration'] === true && creates() === 1, 'Name.com error: domain stays in queue');
    ok(NameComAuditLog::where('action', 'domain.register')->where('response_status', 402)->exists() && DomainLog::where('domain_id', $dom->id)->where('action', 'namecom_register_failed')->exists(), 'failure audited');
    ok(sentTo($clientA, DomainReadyNotification::class) === 0, 'no ready notice on failure');

    // success
    fk(nc());
    $r = sales($staffA, 'register', ['confirm' => true, 'usd_cost' => 21.98], $dom);
    ok($r->getStatusCode() === 200, 'register ok (' . ($r->getStatusCode() === 200 ? '' : json_encode(j($r))) . ')');
    ok(creates() === 1 && posts() === 2, 'exactly ONE create POST (the other POST is the availability lookup)');
    $cq = Http::recorded(fn ($r) => $r->method() === 'POST' && $r->url() === 'https://api.name.com/core/v1/domains')->first()[0];
    $ct = ['firstName' => 'Asha', 'lastName' => 'Mushi', 'address1' => 'Plot 5 Samora Ave', 'city' => 'Dar es Salaam', 'state' => 'Dar es Salaam', 'zip' => '11101', 'country' => 'TZ', 'email' => 'ncs-A@example.test', 'phone' => $clientA->phone];
    $body = $cq->data();
    ok($body['domain']['domainName'] === $name && $body['years'] === 2 && $body['purchaseType'] === 'registration' && !array_key_exists('purchasePrice', $body), 'create body: domain, 2 years, registration, no purchasePrice');
    $cts = $body['domain']['contacts'];
    ok(array_keys($cts) === ['registrant', 'admin', 'tech', 'billing'] && $cts['registrant'] === $cts['admin'] && $cts['registrant']['firstName'] === 'Asha' && $cts['registrant']['country'] === 'TZ' && $cts['registrant']['zip'] === '11101' && str_starts_with($cts['registrant']['phone'], '+255'), 'contacts built from client (E.164 phone, ISO country)');
    $dd = $dom->fresh();
    ok($dd->status === 'active' && $dd->expires_at->toDateString() === '2028-09-27' && $dd->registered_at->toDateString() === '2026-09-27' && !isset($dd->meta['awaiting_manual_registration']) && $dd->meta['namecom']['order'] === 4242 && $dd->meta['unmanaged'] === true, 'domain active with expiry from Name.com, queue flag cleared, linked for nameserver mgmt');
    $au = NameComAuditLog::where('action', 'domain.register')->whereNull('error')->orderByDesc('created_at')->first();
    ok($au && $au->target === $name && $au->request['mode'] === 'manual' && $au->request['years'] === 2 && $au->request['usd_cost'] == 21.98 && $au->user_id === $staffA->id && $au->request['by_user'] === $staffA->id && $au->response_status === 200, 'audit: who/domain/years/usd/mode');
    ok(!str_contains(json_encode(NameComAuditLog::all()->toArray()), 'nc_TEST_TOKEN'), 'audit has no secrets');
    ok(DomainLog::where('domain_id', $dom->id)->where('action', 'namecom_registered')->where('status', 'success')->exists(), 'domain log written');
    ok(sentTo($clientA, DomainReadyNotification::class) === 1, 'customer told "your domain is ready"');
    fk(nc());
    $r = sales($staffA, 'register', ['confirm' => true, 'usd_cost' => 21.98], $dd);
    ok($r->getStatusCode() === 422 && creates() === 0, 'second click cannot buy twice');

    // neutrality after registration
    $ns = json_encode(j(app(PortalDomainController::class)->show(req(Request::create('/x'), $uA), $dd)));
    fk(['api.name.com/core/v1/domains/*' => Http::response(['domainName' => $name, 'nameservers' => ['ns1.name.com', 'ns2.name.com']])]);
    $nsr = j(pdom($uA, 'nameservers', $dd));
    ok(!leaks($ns) && $nsr['data']['provider'] === 'managed' && !preg_match('/namecom/i', json_encode(array_diff_key($nsr, ['data' => 1]))), 'portal show/nameservers neutral (provider=managed, activity has no supplier wording)');
    $pdActivity = json_encode(j(pdom($uA, 'show', $dd))['data']['activity']);
    ok(str_contains($pdActivity, 'Domain registered') && !leaks($pdActivity), 'portal activity: "Domain registered", nothing about the supplier');
    $ready = (new DomainReadyNotification($dd));
    $mail = $ready->toMail($clientA);
    $txt = $mail->subject . ' ' . implode(' ', array_map(fn ($l) => is_string($l) ? $l : '', $mail->introLines)) . ' ' . json_encode($ready->toFcm($clientA));
    ok(str_contains($mail->subject, 'is ready') && !leaks($txt), 'customer notification: "Your domain <name> is ready", neutral');

    // ---------- uncertain outcome (timeout) ----------
    $u1 = Domain::create(['client_id' => $clientA->id, 'name' => 'unc-ncs-test.' . $tdA, 'status' => 'pending', 'meta' => ['unmanaged' => true, 'registrar' => 'namecom', 'awaiting_manual_registration' => true, 'namecom_years' => 2]]);
    fk(nc(['create' => function () { throw new \Illuminate\Http\Client\ConnectionException('timeout'); }]));
    $r = sales($staffA, 'register', ['confirm' => true, 'usd_cost' => 21.98], $u1);
    ok($r->getStatusCode() === 422 && $u1->fresh()->meta['namecom_uncertain'] === true && $u1->fresh()->status === 'pending', 'network timeout: flagged uncertain, stays queued');
    fk(nc(['domain' => Http::response(['domainName' => 'unc-ncs-test.' . $tdA, 'createDate' => '2026-09-27T10:00:00Z', 'expireDate' => '2028-09-27T10:00:00Z', 'nameservers' => ['ns1.name.com']])]));
    $r = sales($staffA, 'register', ['confirm' => true, 'usd_cost' => 21.98], $u1);
    ok($r->getStatusCode() === 200 && creates() === 0 && $u1->fresh()->status === 'active', 'retry after uncertain: found in Name.com account -> adopted, NO second purchase');

    // ---------- auto mode ----------
    $mkQ = fn ($tag, $years = 1) => Domain::create(['client_id' => $clientA->id, 'name' => "$tag-ncs-test.$tdA", 'status' => 'pending', 'meta' => ['unmanaged' => true, 'registrar' => 'namecom', 'awaiting_manual_registration' => true, 'namecom_years' => $years]]);
    $svc = app(NameComRegistrationService::class);
    $q1 = $mkQ('auto1');
    fk(nc());
    $r = $svc->autoRegister($q1);
    ok($r['registered'] === false && creates() === 0 && hits() === 0, 'auto setting OFF: autoRegister does nothing (no calls)');
    $set = fn (array $o) => sales($staffA, 'saveSettings', $o + ['usd_rate' => 3000, 'fixed_markup' => 10000, 'auto_register' => true, 'auto_cap_usd' => 50, 'auto_daily_limit' => 2]);
    $set([]);
    Bus::fake();
    $dq = mkClient('dq', $fullAddr); $ddoc = Document::create(['client_id' => $dq->id, 'type' => 'invoice', 'document_number' => 'NCS-' . random_int(1000, 99999), 'date' => now()->toDateString(), 'due_date' => now()->toDateString(), 'subtotal' => 1, 'total' => 1, 'status' => 'sent']);
    $qd = Domain::create(['client_id' => $dq->id, 'name' => 'hook-ncs-test.' . $tdA, 'status' => 'pending', 'meta' => ['unmanaged' => true, 'registrar' => 'namecom', 'pending_action' => 'register', 'pending_years' => 1, 'namecom_years' => 1, 'order_document_id' => $ddoc->id]]);
    $ddoc->update(['status' => 'paid']);
    ok(Bus::dispatched(AutoRegisterNameComDomainJob::class)->count() === 1 && $qd->fresh()->meta['awaiting_manual_registration'] === true && $qd->fresh()->status === 'pending', 'auto ON: paid hook queues the guarded job (domain still in queue until it runs)');
    Bus::fake([]);

    fk(nc(['live' => 10.99]));
    $r = $svc->autoRegister($q1);
    ok($r['registered'] === true && creates() === 1 && $q1->fresh()->status === 'active', 'auto ON within cap: registers via the same service (one create)');
    $au = NameComAuditLog::where('action', 'domain.register')->whereNull('error')->where('target', $q1->name)->first();
    ok($au && $au->request['mode'] === 'auto', 'auto registration audited with mode=auto');
    $q2 = $mkQ('auto2');
    fk(nc(['live' => 60.00]));
    $r = $svc->autoRegister($q2);
    ok($r['registered'] === false && str_contains($r['reason'], 'cap') && creates() === 0 && $q2->fresh()->meta['awaiting_manual_registration'] === true, 'USD cost above cap ($50): no create, stays in manual queue');
    ok(sentTo($staffA, NameComRegistrationPendingNotification::class) >= 2, 'staff notified that auto did not run');
    $set(['auto_cap_usd' => 100]);
    fk(nc(['live' => 20.00]));
    $r = $svc->autoRegister($q2);
    ok($r['registered'] === false && str_contains($r['reason'], 'higher than the synced') && creates() === 0, 'live price above synced price: refused -> manual');
    fk(nc(['avail' => false]));
    $r = $svc->autoRegister($q2);
    ok($r['registered'] === false && creates() === 0, 'failed availability re-check: falls back to manual queue');
    fk(nc(['live' => 11.99]));
    $r = $svc->autoRegister($q2);
    ok($r['registered'] === true, 'second auto registration within limit ok');
    $q3 = $mkQ('auto3');
    fk(nc(['live' => 11.99]));
    $r = $svc->autoRegister($q3);
    ok($r['registered'] === false && str_contains($r['reason'], 'Daily') && creates() === 0 && $q3->fresh()->meta['awaiting_manual_registration'] === true, 'daily limit (2) reached: refused -> manual queue');
    fk(nc(['create' => Http::response(['message' => 'boom'], 500), 'live' => 11.99]));
    $set(['auto_daily_limit' => 10]);
    $r = $svc->autoRegister($q3);
    ok($r['registered'] === false && $q3->fresh()->status === 'pending' && $q3->fresh()->meta['awaiting_manual_registration'] === true, 'Name.com failure in auto mode: left in manual queue');
    $set(['auto_register' => false]);

    // ---------- renewals stay manual ----------
    $reg = Domain::where('name', $name)->first();
    fk([]);
    $rdoc = app(DomainBillingService::class)->createRenewalInvoice($reg, 1);
    ok((float) $rdoc->total === (float) DomainTld::where('tenant_id', $tenantA->id)->where('tld', $tdA)->value('renew_price') && $reg->fresh()->meta['pending_action'] === 'renew', 'renewal invoice for a registered Name.com domain works (renew TZS price)');
    DomainTld::where('tenant_id', $tenantA->id)->where('tld', $tdA)->update(['is_active' => false]);
    $rdoc = app(DomainBillingService::class)->createRenewalInvoice($reg->fresh(), 1);
    ok($rdoc->id !== null, 'renewal still billable even if the TLD is later taken off sale');
    DomainTld::where('tenant_id', $tenantA->id)->where('tld', $tdA)->update(['is_active' => true]);
    $rdoc->update(['status' => 'paid']);
    ok($reg->fresh()->meta['pending_manual_renewal'] === true && hits() === 0, 'paid renewal -> manual queue flag, no Name.com call');

    // ---------- allow-list ----------
    $refuse = function (string $m, string $p, bool $c = false) { try { NameComDriver::assertAllowed($m, $p, $c); return false; } catch (NameComApiException) { return true; } };
    ok($refuse('POST', '/core/v1/domains') && !$refuse('POST', '/core/v1/domains', true), 'POST /core/v1/domains only with the create authorisation');
    foreach ([['DELETE', '/core/v1/domains/a.com'], ['PUT', '/core/v1/domains'], ['POST', '/core/v1/domains/a.com:renew'], ['POST', '/core/v1/domains/a.com:purchase'], ['POST', '/core/v1/transfers'],
        ['POST', '/core/v1/tldpricing'], ['GET', '/core/v1/tldpricing/com'], ['GET', '/core/v1/domains:checkAvailability'], ['POST', '/core/v1/domains:search'], ['POST', '/core/v1/domains/a.com:setContacts'],
        ['DELETE', '/core/v1/domains', true], ['PATCH', '/core/v1/domains', true], ['POST', '/core/v1/domains/a.com', true], ['POST', '/core/v1/domains:checkAvailability/x'], ['GET', '/core/v1/orders'], ['POST', '/core/v1/refund']] as $t) {
        ok($refuse($t[0], $t[1], $t[2] ?? false), "refused {$t[0]} {$t[1]}");
    }
    ok(!$refuse('GET', '/core/v1/tldpricing') && !$refuse('POST', '/core/v1/domains:checkAvailability'), 'allowed: GET tldpricing, POST checkAvailability');
    $drv = new NameComDriver($account);
    try { $drv->createDomain(new \stdClass, 'a.com', 1, []); ok(false, 'createDomain typed to service'); } catch (\TypeError) { ok(true, 'createDomain cannot be called without NameComRegistrationService'); }
    $m = new ReflectionMethod($drv, 'request'); $m->setAccessible(true);
    fk([]);
    try { $m->invoke($drv, 'POST', '/core/v1/domains', [], ['domain' => ['domainName' => 'a.com']]); ok(false, 'raw create'); } catch (NameComApiException) { ok(hits() === 0, 'raw wrapper refuses POST /core/v1/domains without the flag: zero HTTP'); }

    // ---------- permissions ----------
    $gates = collect(app('router')->getRoutes())->filter(fn ($r) => str_starts_with($r->uri(), 'api/namecom'))
        ->mapWithKeys(fn ($r) => [$r->methods()[0] . ' ' . $r->uri() => collect($r->gatherMiddleware())->first(fn ($m) => str_starts_with($m, 'permission:'))]);
    ok($gates['GET api/namecom/settings'] === 'permission:domains.settings' && $gates['PUT api/namecom/settings'] === 'permission:domains.settings' && $gates['POST api/namecom/tlds/sync'] === 'permission:domains.settings' && $gates['PUT api/namecom/tlds/{tld}'] === 'permission:domains.settings' && $gates['GET api/namecom/tlds'] === 'permission:domains.settings', 'settings/sync/pricing routes need domains.settings');
    ok($gates['POST api/namecom/registration/{domain}'] === 'permission:domains.create' && $gates['GET api/namecom/registration/{domain}'] === 'permission:domains.create', 'register action needs domains.create');
    ok($gates->every(fn ($g) => $g !== null), 'every namecom route is permission-gated');
    $noPerm = User::withoutGlobalScopes()->whereNotNull('tenant_id')->whereNotNull('role_id')->get()->first(fn ($u) => !$u->isSuperAdmin() && !$u->hasAnyPermission(['domains.settings', 'domains.create']));
    if ($noPerm) {
        foreach (['domains.settings', 'domains.create'] as $perm) {
            $rq = Request::create('/x'); $rq->setUserResolver(fn () => $noPerm);
            ok((new CheckPermission())->handle($rq, fn () => response('ok'), $perm)->getStatusCode() === 403, "user without $perm gets 403");
        }
    } else echo "SKIP no user without domains perms\n";

    // ---------- tenant isolation ----------
    $other = User::withoutGlobalScopes()->where('tenant_id', $tenantB->id)->first();
    if ($other) {
        auth()->setUser($other);
        $r = sales($other, 'tlds', []);
        ok(j($r)['counts']['total'] === 0 && j($r)['settings']['usd_rate'] == 3000 && j($r)['settings']['auto_register'] === false, 'tenant B sees none of tenant A TLDs and its own default settings');
        ok(sales($other, 'updateTld', ['is_active' => false], $tdA)->getStatusCode() === 404, "tenant B cannot edit tenant A's TLD");
        ok(Domain::where('name', $name)->doesntExist() && NameComAuditLog::count() === 0 && NameComSettings::count() === 0, 'tenant B cannot see A domains/audit/settings');
        $r = sales($other, 'sync');
        ok($r->getStatusCode() === 422, "tenant B without Name.com credentials cannot sync (no borrowing A's account)");
    } else echo "SKIP no tenant B user\n";
    auth()->setUser($staffA);
} catch (\Throwable $e) {
    $fail++; echo "EXCEPTION: " . $e->getMessage() . "\n" . $e->getFile() . ':' . $e->getLine() . "\n";
} finally {
    DB::rollBack();
}
echo $fail ? "\n$fail FAILED\n" : "\nALL PASSED\n";
exit($fail ? 1 : 0);
