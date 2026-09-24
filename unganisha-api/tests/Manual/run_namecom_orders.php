<?php
// php tests/Manual/run_namecom_orders.php  (live DB rolled back; Http::fake + preventStrayRequests - NO real calls)
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Http\Controllers\{DomainController, DomainTldController};
use App\Http\Controllers\Portal\PortalOrderController;
use App\Models\{Client, ClientUser, Document, Domain, DomainTld, NameComAccount, Tenant, User};
use App\Services\Registrar\NameComDriver;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\{DB, Http};

NameComDriver::$sleepOnRateLimit = false;
$fail = 0;
function ok($c, $m) { global $fail; if (!$c) { $fail++; echo "FAIL $m\n"; } else echo "PASS $m\n"; }
function fk($x) { Http::swap(new \Illuminate\Http\Client\Factory()); Http::preventStrayRequests(); Http::fake($x); }
function j($r) { return $r->getData(true); }
function req(Request $rq, $u) { $rq->setUserResolver(fn () => $u); app()->instance('request', $rq); auth()->setUser($u); return $rq; }
function trap(callable $f) {
    try { return $f(); }
    catch (\Illuminate\Validation\ValidationException $e) { return response()->json(['message' => $e->getMessage()], 422); }
}
function checks() { return Http::recorded(fn ($r) => str_contains($r->url(), ':checkAvailability'))->count(); }
function fakeNc() {
    return ['api.name.com/core/v1/domains:checkAvailability' => fn ($r) => Http::response(['results' => [['domainName' => $r['domainNames'][0], 'sld' => 'x', 'tld' => 'y', 'purchasable' => true, 'premium' => false, 'purchaseType' => 'registration', 'purchasePrice' => 10.99, 'renewalPrice' => 12.99]]])];
}
function sorder($u, array $d) { $rq = req(Request::create('/x', 'POST', $d), $u); return trap(fn () => app(DomainController::class)->order($rq)); }
function stlds($u, array $q = []) { $rq = req(Request::create('/x', 'GET', $q), $u); return j(app(PortalOrderController::class)->tlds($rq)); }

DB::beginTransaction();
try {
    $tenant = Tenant::withoutGlobalScopes()->where('name', 'MoBilling Test Co')->firstOrFail();
    $staff = User::withoutGlobalScopes()->where('tenant_id', $tenant->id)->firstOrFail();
    auth()->setUser($staff);
    NameComAccount::create(['username' => 'owner', 'token' => 'nc_TEST_TOKEN_abcdefghijklmnop', 'token_hint' => 'mnop', 'is_sandbox' => false, 'status' => 'active']);
    $client = Client::create(['name' => 'NC Orders TEST', 'phone' => '25570' . random_int(1000000, 9999999), 'email' => 'nco@example.test', 'status' => 'active']);

    $T = 'ncordx'; // unique test TLD: platform placeholder + tenant Name.com row
    $Z = 'ncordz'; // plain FRED-style manual TLD
    DomainTld::create(['tenant_id' => null, 'tld' => $T, 'register_price' => 55000, 'renew_price' => 55000, 'transfer_price' => 55000, 'registrar' => 'fred', 'is_unmanaged' => true, 'is_active' => true, 'years_min' => 1, 'years_max' => 10]);
    $nc = DomainTld::create(['tenant_id' => $tenant->id, 'tld' => $T, 'register_price' => 48970, 'renew_price' => 52970, 'transfer_price' => 0, 'registrar' => 'namecom', 'is_unmanaged' => true, 'is_active' => false, 'years_min' => 1, 'years_max' => 10]);
    DomainTld::create(['tenant_id' => $tenant->id, 'tld' => $Z, 'register_price' => 7000, 'renew_price' => 8000, 'transfer_price' => 6000, 'registrar' => 'fred', 'is_unmanaged' => true, 'is_active' => true, 'years_min' => 1, 'years_max' => 10]);

    // ---- off sale: pickers never show the placeholder, order refused with the enable hint
    $hosting = stlds($staff)['data'];
    ok(!collect($hosting)->contains('tld', $T), 'hosting/bundled picker: off-sale Name.com TLD hidden, placeholder NOT used as fallback');
    ok(collect($hosting)->contains('tld', $Z), 'hosting picker still lists normal TLD');
    $dom = stlds($staff, ['scope' => 'domain']);
    ok(!collect($dom['data'])->contains('tld', $T) && in_array($T, $dom['off_sale'], true), 'staff domain picker: TLD absent from data, listed in off_sale');
    $catalog = app(DomainTldController::class)->index()->getData(true)['data'];
    ok(!collect($catalog)->contains('tld', $T), 'Settings TLD list hides the platform placeholder shadowed by the Name.com row');

    fk(fakeNc());
    $n0 = Document::count();
    $r = sorder($staff, ['name' => "off-nco.$T", 'client_id' => $client->id, 'years' => 1, 'action' => 'register']);
    $msg = j($r)['message'] ?? '';
    ok($r->getStatusCode() === 422 && str_contains($msg, "Enable .$T in Settings > Domains > Name.com > TLDs & pricing"), 'off-sale order refused with enable message');
    ok(Document::count() === $n0 && Domain::where('name', "off-nco.$T")->doesntExist(), 'no invoice/domain created with the 55,000 placeholder');
    ok(checks() === 0, 'no availability call for off-sale TLD');

    // ---- on sale
    $nc->update(['is_active' => true]);
    $dom = stlds($staff, ['scope' => 'domain']);
    $row = collect($dom['data'])->firstWhere('tld', $T);
    ok($row && $row["register_price"] == 48970 && $row['via'] === 'namecom' && !in_array($T, $dom['off_sale'], true), 'staff picker gives formula price 48,970 (not 55,000), via namecom');
    ok(!collect(stlds($staff)['data'])->contains('tld', $T), 'bundled hosting picker still excludes Name.com TLD (ordered separately)');

    fk(fakeNc());
    $r = sorder($staff, ['name' => "one-nco.$T", 'client_id' => $client->id, 'years' => 1, 'action' => 'register']);
    ok($r->getStatusCode() === 201, 'on-sale order created (' . ($r->getStatusCode() === 201 ? 'ok' : json_encode(j($r))) . ')');
    ok(checks() === 1, 'exactly one checkAvailability call');
    $doc = Document::find(j($r)['document']['id'] ?? null);
    ok((float) $doc->total === 48970.0 && (float) $doc->items()->first()->price === 48970.0, '1 year invoice = 48,970');
    ok(j($r)['document']['total'] == $doc->total && str_contains(j($r)['message'], 'registration queue'), 'response total consistent with picker price; message says registration queue');
    $d = Domain::where('name', "one-nco.$T")->first();
    ok($d->status === 'pending' && $d->registrar_account_id === null && $d->meta['registrar'] === 'namecom' && $d->meta['namecom_years'] === 1 && $d->meta['order_document_id'] === $doc->id, 'pending Name.com domain, no FRED account, linked to invoice');

    fk(fakeNc());
    $r = sorder($staff, ['name' => "three-nco.$T", 'client_id' => $client->id, 'years' => 3, 'action' => 'register']);
    $doc = Document::find(j($r)['document']['id'] ?? null);
    ok($r->getStatusCode() === 201 && (float) $doc->total === round(48970 * 3, 2) && Domain::where('name', "three-nco.$T")->first()->meta['namecom_years'] === 3, '3 years invoice = 3 x 48,970, years recorded');
    ok(sorder($staff, ['name' => "tr-nco.$T", 'client_id' => $client->id, 'years' => 1, 'action' => 'transfer', 'auth_info' => 'x'])->getStatusCode() === 422, 'transfer of Name.com TLD refused');

    // ---- .tz / manual path unchanged
    fk(['*' => Http::response([], 500)]);
    $r = sorder($staff, ['name' => "plain-nco.$Z", 'client_id' => $client->id, 'years' => 2, 'action' => 'register']);
    $doc = Document::find(j($r)['document']['id'] ?? null);
    $pd = Domain::where('name', "plain-nco.$Z")->first();
    ok($r->getStatusCode() === 201 && (float) $doc->total === 14000.0 && empty($pd->meta['registrar']) && !str_contains(j($r)['message'], 'registration queue'), 'manual/FRED-style TLD order unchanged (2 x 7,000, no Name.com routing)');
    ok(Http::recorded(fn ($q) => str_contains($q->url(), 'name.com'))->count() === 0, 'non-Name.com TLD made no Name.com call');

    // ---- portal/client responses neutral
    $cu = ClientUser::create(['client_id' => $client->id, 'tenant_id' => $tenant->id, 'name' => 'U nco', 'email' => 'nco-u@example.test', 'password' => 'x-Secret-123', 'role' => 'admin', 'is_active' => true]);
    if ($cu) {
        $pc = json_encode(stlds($cu, ['scope' => 'domain']));
        ok(!preg_match('/namecom|name\.com|off_sale|"via"/i', $pc), 'portal/client TLD response neutral (scope=domain ignored for clients)');
    } else echo "SKIP no client user\n";
} catch (\Throwable $e) {
    $fail++; echo "EXCEPTION: " . $e->getMessage() . "\n" . $e->getFile() . ':' . $e->getLine() . "\n";
} finally {
    DB::rollBack();
}
echo $fail ? "\n$fail FAILED\n" : "\nALL PASSED\n";
exit($fail ? 1 : 0);
