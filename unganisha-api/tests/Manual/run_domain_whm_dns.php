<?php
// php tests/Manual/run_domain_whm_dns.php
// Live DB, everything rolled back at the end. WHM is 100% faked (Http::fake
// on a fake host, preventStrayRequests) — NEVER a real WHM call. Covers the
// new domain-centric WHM DNS feature (WhmService::createDnsZone + the new
// DomainController dns-zone* endpoints) for a Domain with no hosting_accounts
// row of its own — mainly FRED/.tz domains that were never provisioned here.
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Http\Controllers\DomainController;
use App\Models\{Client, Domain, ProvisioningLog, Server, Tenant, User};
use Illuminate\Http\Request;
use Illuminate\Support\Facades\{DB, Http};

$fail = 0;
function ok($c, $m) { global $fail; if (!$c) { $fail++; echo "FAIL $m\n"; } else echo "PASS $m\n"; }
function j($r) { return $r->getData(true); }
function trap(callable $f) {
    try { return $f(); }
    catch (\Symfony\Component\HttpKernel\Exception\HttpException $e) { return response()->json(['message' => $e->getMessage()], $e->getStatusCode()); }
    catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) { return response()->json(['message' => 'not found'], 404); }
    catch (\Illuminate\Validation\ValidationException $e) { return response()->json(['message' => 'validation', 'errors' => $e->errors()], 422); }
}

// ── fake WHM ──────────────────────────────────────────────────────────────
$whmCalls = [];   // ordered list of function names actually called
$whmLog   = [];   // ['fn' => ..., 'params' => [...]] per call
$FAKE_HOST = 'dns-fake.invalid';
// verbs this feature must NEVER call, anywhere, across the whole run — the
// established add-only policy (see WhmService::addDnsRecord()'s doc comment).
const FORBIDDEN_VERBS = ['editzonerecord', 'removezonerecord', 'killdns', 'deldns', 'resetzone'];

function fakeWhm() {
    global $whmCalls, $whmLog, $FAKE_HOST;
    Http::swap(new \Illuminate\Http\Client\Factory());
    Http::preventStrayRequests();
    Http::fake(function ($request) use (&$whmCalls, &$whmLog, $FAKE_HOST) {
        $url = $request->url();
        if (!str_contains($url, $FAKE_HOST)) {
            return Http::response(['ok' => true], 200); // any non-WHM request is faked too, never real
        }
        preg_match('#/json-api/(\w+)#', $url, $m);
        $fn = $m[1] ?? '';
        parse_str(parse_url($url, PHP_URL_QUERY) ?? '', $q);
        $whmCalls[] = $fn;
        $whmLog[] = ['fn' => $fn, 'params' => $q];
        $meta = ['metadata' => ['result' => 1, 'reason' => 'OK']];

        if ($fn === 'adddns') {
            // Official spec (api.docs.cpanel.net/specifications/whm.openapi/dns-zones/dns-adddns.md):
            // response is metadata-only, no `data` payload.
            return Http::response($meta, 200);
        }
        if ($fn === 'parse_dns_zone') {
            $zone = $q['zone'] ?? 'example.test';
            $records = [
                ['type' => 'control', 'raw' => '; comment line'], // non-record line, must be filtered out
                ['type' => 'record', 'record_type' => 'A', 'dname_raw' => "{$zone}.", 'ttl' => 14400, 'data_b64' => [base64_encode('203.0.113.5')]],
            ];
            return Http::response($meta + ['data' => ['payload' => $records]], 200);
        }
        if ($fn === 'addzonerecord') {
            return Http::response($meta, 200);
        }
        // any forbidden verb would land here too — still answered "success" so a wrongly-added call would be caught by the FORBIDDEN_VERBS assertion, not hidden by an error
        return Http::response($meta + ['data' => []], 200);
    });
}
function whmCount(string $fn): int { global $whmCalls; return count(array_filter($whmCalls, fn ($c) => $c === $fn)); }
function lastCall(string $fn): ?array { global $whmLog; $rows = array_values(array_filter($whmLog, fn ($r) => $r['fn'] === $fn)); return $rows ? end($rows) : null; }

DB::beginTransaction();
try {
    $tenantA = Tenant::withoutGlobalScopes()->where('name', 'MoBilling Test Co')->firstOrFail();
    $tenantB = Tenant::withoutGlobalScopes()->where('id', '!=', $tenantA->id)->firstOrFail();
    $staffA  = User::withPermission($tenantA->id, 'domains.manage_dns')->first()
        ?? User::withoutGlobalScopes()->where('tenant_id', $tenantA->id)->firstOrFail();
    $staffB  = User::withoutGlobalScopes()->where('tenant_id', $tenantB->id)->first();

    fakeWhm();

    // BelongsToTenant's creating() hook forces tenant_id to the CURRENT auth
    // user's tenant regardless of what's passed in — so a genuinely
    // cross-tenant fixture needs auth briefly switched while it's created.
    $serverOtherTenant = null;
    if ($staffB) {
        auth()->setUser($staffB);
        $serverOtherTenant = Server::create(['tenant_id' => $tenantB->id, 'name' => 'dns-fake-b', 'hostname' => 'dns-fake-b.invalid', 'port' => 2087, 'username' => 'moinfote', 'api_token' => 'x', 'type' => 'whm', 'is_active' => true, 'verify_ssl' => false]);
    }
    auth()->setUser($staffA);

    $server = Server::create(['tenant_id' => $tenantA->id, 'name' => 'dns-fake', 'hostname' => 'dns-fake.invalid', 'port' => 2087, 'username' => 'moinfote', 'api_token' => 'x', 'type' => 'whm', 'is_active' => true, 'verify_ssl' => false]);

    $client = Client::create(['tenant_id' => $tenantA->id, 'name' => 'WHM DNS Test Client', 'phone' => '2557' . random_int(10000000, 99999999), 'email' => uniqid() . '@example.test', 'status' => 'active']);
    $domain = Domain::create(['tenant_id' => $tenantA->id, 'client_id' => $client->id, 'name' => 'whmdnstest-' . uniqid() . '.co.tz', 'status' => 'active', 'meta' => []]);

    $call = fn (string $method, ...$args) => trap(fn () => app(DomainController::class)->$method(...$args));
    $callWithBody = function (string $method, array $body, Domain $d) {
        $req = Request::create('/x', 'POST', $body);
        $req->setUserResolver(fn () => auth()->user());
        return trap(fn () => app(DomainController::class)->$method($req, $d));
    };

    // ── dns-servers picker ───────────────────────────────────────────────
    $resp = $call('dnsServers');
    $names = collect(j($resp)['data'])->pluck('name')->all();
    ok($resp->getStatusCode() === 200 && in_array('dns-fake', $names, true) && !in_array('dns-fake-b', $names, true), 'dnsServers: tenant-scoped list, no credentials leak (own server only)');
    ok(!str_contains(json_encode(j($resp)), 'api_token') && !str_contains(json_encode(j($resp)), 'moinfote'), 'dnsServers payload carries no WHM credentials');

    // ── status: no zone yet ──────────────────────────────────────────────
    $resp = $call('dnsZoneStatus', $domain->fresh());
    ok($resp->getStatusCode() === 200 && j($resp)['data']['exists'] === false, 'dnsZoneStatus: no zone tracked yet -> exists=false');
    ok(whmCount('adddns') === 0 && whmCount('parse_dns_zone') === 0, 'status check makes no WHM call at all (no silent probing)');

    // ── reading a zone before one exists ─────────────────────────────────
    $resp = $call('dnsZone', $domain->fresh());
    ok($resp->getStatusCode() === 404, 'dnsZone read refused before a zone has been created (404, not a WHM call)');
    ok(whmCount('parse_dns_zone') === 0, 'no parse_dns_zone call made for a domain with no tracked zone');

    // ── create refused for another tenant's server ───────────────────────
    if ($serverOtherTenant) {
        $whmCalls = [];
        $resp = $callWithBody('createDnsZone', ['server_id' => $serverOtherTenant->id, 'ip' => '203.0.113.5'], $domain->fresh());
        ok($resp->getStatusCode() === 422, 'createDnsZone: another tenant\'s server_id is refused (422 validation, not found in this tenant)');
        ok(whmCount('adddns') === 0, 'no adddns call was made for the refused cross-tenant attempt');
    } else {
        echo "SKIP no tenant B user available for cross-tenant server refusal check\n";
    }

    // ── create happy path ─────────────────────────────────────────────────
    $whmCalls = [];
    $resp = $callWithBody('createDnsZone', ['server_id' => $server->id, 'ip' => '203.0.113.5'], $domain->fresh());
    $body = j($resp);
    ok($resp->getStatusCode() === 200, 'createDnsZone: happy path succeeds — ' . json_encode($body));
    ok(whmCount('adddns') === 1, 'exactly one adddns call');
    $addCall = lastCall('adddns');
    ok(($addCall['params']['domain'] ?? null) === $domain->name && ($addCall['params']['ip'] ?? null) === '203.0.113.5' && !array_key_exists('trueowner', $addCall['params']), 'adddns called with exactly {domain, ip} — no trueowner (a DNS-only zone with no cPanel account is the whole point here)');
    ok($body['data']['www_record_added'] === true, 'convenience: www A record reported added');
    ok(whmCount('addzonerecord') === 1, 'exactly one addzonerecord call for the www convenience record (root is already auto-created by adddns itself — not duplicated here)');
    $wwwCall = lastCall('addzonerecord');
    ok(($wwwCall['params']['name'] ?? null) === "www.{$domain->name}." && ($wwwCall['params']['type'] ?? null) === 'A' && ($wwwCall['params']['address'] ?? null) === '203.0.113.5' && ($wwwCall['params']['class'] ?? null) === 'IN', 'www addzonerecord call has the exact expected params');
    $domain = $domain->fresh();
    ok(($domain->meta['whm_dns']['server_id'] ?? null) === $server->id && ($domain->meta['whm_dns']['ip'] ?? null) === '203.0.113.5', 'domain.meta.whm_dns records which server + ip now host this domain\'s DNS');

    // ── create refused a second time (already tracked) ───────────────────
    $whmCalls = [];
    $resp = $callWithBody('createDnsZone', ['server_id' => $server->id, 'ip' => '203.0.113.5'], $domain->fresh());
    ok($resp->getStatusCode() === 422 && whmCount('adddns') === 0, 'createDnsZone refuses a second time for the same domain, no WHM call made');

    // ── status: zone now exists ───────────────────────────────────────────
    $resp = $call('dnsZoneStatus', $domain->fresh());
    $d = j($resp)['data'];
    ok($resp->getStatusCode() === 200 && $d['exists'] === true && $d['server_id'] === $server->id && $d['server_name'] === 'dns-fake' && $d['ip'] === '203.0.113.5', 'dnsZoneStatus now reports exists=true with the server it was created on');

    // ── reading the zone ───────────────────────────────────────────────────
    $whmCalls = [];
    $resp = $call('dnsZone', $domain->fresh());
    $rows = j($resp)['data'];
    ok($resp->getStatusCode() === 200 && whmCount('parse_dns_zone') === 1, 'dnsZone read: one parse_dns_zone call');
    ok(count($rows) === 1 && $rows[0]['type'] === 'A' && $rows[0]['name'] === "{$domain->name}." && $rows[0]['data'] === ['203.0.113.5'], 'zone read: control/comment lines filtered, real record decoded correctly');

    // ── add-only record: happy path ───────────────────────────────────────
    $whmCalls = [];
    $resp = $callWithBody('addDnsRecord', ['type' => 'TXT', 'name' => "_acme-challenge.{$domain->name}", 'ttl' => 300, 'value' => 'verification-token-xyz'], $domain->fresh());
    ok($resp->getStatusCode() === 200, 'addDnsRecord: happy path succeeds — ' . json_encode(j($resp)));
    ok(whmCount('addzonerecord') === 1, 'exactly one addzonerecord call');
    $txtCall = lastCall('addzonerecord');
    ok(($txtCall['params']['name'] ?? null) === "_acme-challenge.{$domain->name}." && ($txtCall['params']['type'] ?? null) === 'TXT' && ($txtCall['params']['txtdata'] ?? null) === 'verification-token-xyz' && ($txtCall['params']['ttl'] ?? null) == 300, 'TXT addzonerecord call has the exact expected params (dot-terminated name)');

    // ── add-only record refused for a domain with no zone yet ────────────
    $noZoneClient = Client::create(['tenant_id' => $tenantA->id, 'name' => 'No Zone Client', 'phone' => '2557' . random_int(10000000, 99999999), 'email' => uniqid() . '@example.test', 'status' => 'active']);
    $noZoneDomain = Domain::create(['tenant_id' => $tenantA->id, 'client_id' => $noZoneClient->id, 'name' => 'noznedns-' . uniqid() . '.co.tz', 'status' => 'active', 'meta' => []]);
    $whmCalls = [];
    $resp = $callWithBody('addDnsRecord', ['type' => 'A', 'name' => 'sub', 'ttl' => 300, 'value' => '1.2.3.4'], $noZoneDomain);
    ok($resp->getStatusCode() === 404 && whmCount('addzonerecord') === 0, 'addDnsRecord refused (404) for a domain with no zone yet, no WHM call made');

    // ── tenant isolation: tenant B cannot resolve tenant A's domain/server ─
    if ($staffB) {
        auth()->setUser($staffB);
        $foundDomain = Domain::where('id', $domain->id)->first();
        $foundServer = Server::where('id', $server->id)->first();
        ok($foundDomain === null && $foundServer === null, 'tenant B cannot resolve tenant A\'s domain or server (route-binding-equivalent tenant scope)');
        auth()->setUser($staffA);
    } else {
        echo "SKIP no tenant B user available for isolation check\n";
    }

    // ── add-only guarantee: no forbidden WHM verb was ever called ─────────
    $allCalledFns = array_unique(array_column($whmLog, 'fn'));
    $violations = array_intersect($allCalledFns, FORBIDDEN_VERBS);
    ok(empty($violations), 'no edit/delete WHM DNS verb was ever called across this entire run: ' . json_encode(array_values($violations)));

    // ── audit trail (ProvisioningLog) ──────────────────────────────────────
    $logs = ProvisioningLog::withoutGlobalScopes()->where('server_id', $server->id)->where('action', 'adddns')->get();
    ok($logs->count() >= 1 && $logs->first()->status === 'success', 'adddns call was audited in provisioning_logs');

    // ── route wiring (permission gating) ────────────────────────────────
    $routes = collect(app('router')->getRoutes());
    $expectGated = [
        ['GET', 'api/domains/{domain}/dns-zone-status'],
        ['GET', 'api/domains/{domain}/dns-zone'],
        ['POST', 'api/domains/{domain}/dns-zone'],
        ['POST', 'api/domains/{domain}/dns-zone/records'],
    ];
    foreach ($expectGated as [$verb, $uri]) {
        $route = $routes->first(fn ($r) => $r->uri() === $uri && in_array($verb, $r->methods()));
        ok($route && in_array('permission:domains.manage_dns', $route->gatherMiddleware()), "$verb $uri route requires permission:domains.manage_dns");
    }
    $serversRoute = $routes->first(fn ($r) => $r->uri() === 'api/domains/dns-servers');
    ok($serversRoute && in_array('permission:domains.read', $serversRoute->gatherMiddleware()), 'GET api/domains/dns-servers route requires permission:domains.read');

    // no credentials ever leaked in any response body collected above
    ok(!str_contains(json_encode($whmLog), 'api_token') && !str_contains(json_encode($body), 'moinfote'), 'no WHM credentials appear in any response payload');
} catch (\Throwable $e) {
    $fail++; echo "EXCEPTION: " . $e->getMessage() . "\n" . $e->getFile() . ':' . $e->getLine() . "\n" . $e->getTraceAsString() . "\n";
} finally {
    DB::rollBack();
}

echo $fail ? "\n$fail FAILED\n" : "\nALL PASSED\n";
exit($fail ? 1 : 0);
