<?php
// php tests/Manual/run_namecom_manager.php  (live DB rolled back; Name.com fully faked, Http::preventStrayRequests - NO real calls)
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Exceptions\NameComApiException;
use App\Http\Controllers\Portal\PortalDomainController;
use App\Http\Controllers\Portal\PortalDomainManagerController as C;
use App\Models\{Client, ClientUser, Domain, DomainLog, NameComAccount, NameComAuditLog, Tenant, User};
use App\Notifications\DomainManagerActivityNotification;
use App\Services\Registrar\{NameComDriver, NameComManagerService as M};
use Illuminate\Http\Request;
use Illuminate\Support\Facades\{DB, Http, Log, Notification};

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
    catch (\Illuminate\Validation\ValidationException $e) { return response()->json(['message' => 'validation', 'errors' => $e->errors()], 422); }
}
$PORTAL = [];
/** Call a manager controller method as a portal user. */
function pc(ClientUser $u, string $m, Domain $d, array $b = [], ?string $arg = null) {
    global $PORTAL;
    $rq = req(Request::create('/x', 'POST', $b), $u);
    $r = trap(fn () => $arg === null ? app(C::class)->$m($rq, $d) : app(C::class)->$m($rq, $d, $arg));
    $PORTAL[] = $r->getContent();
    return $r;
}
function dom(string $n, array $x = []) { return array_merge(['domainName' => $n, 'createDate' => '2020-01-05T10:00:00Z', 'expireDate' => '2031-03-04T10:00:00Z', 'locked' => true, 'autorenewEnabled' => false, 'nameservers' => ['ns1.name.com', 'ns2.name.com']], $x); }
function user($r) { return explode(':', base64_decode(substr($r->header('Authorization')[0] ?? '', 6)))[0]; }
function contact($n) { return ['firstName' => $n, 'lastName' => 'Doe', 'companyName' => '', 'address1' => '1 Main St', 'city' => 'Dar', 'state' => 'DSM', 'zip' => '11101', 'country' => 'TZ', 'email' => strtolower($n) . '@example.test', 'phone' => '+255712345678', 'isVerified' => true];
}
/**
 * Stateful fake of the registrar API. $S = [domain => [records, url, mail, hosts, contacts, ns]]; $own = username => domains.
 * $fail = HTTP status to answer every call with (null = normal).
 */
function fakeNc(array $own, array &$S, ?int $failStatus = null) {
    return ['api.name.com/*' => function ($r) use ($own, &$S, $failStatus) {
        $u = user($r); $path = parse_url($r->url(), PHP_URL_PATH); $m = $r->method(); $body = json_decode($r->body(), true) ?? [];
        if ($failStatus) return Http::response(['message' => 'X', 'details' => 'SECRET-INTERNAL Name.com detail'], $failStatus);
        if (!preg_match('#^/core/v1/(?:domains|urlforwarding)/([a-z0-9.-]+)([:/].*)?$#', $path, $mm)) return Http::response([], 200);
        $n = $mm[1]; $rest = $mm[2] ?? '';
        if (!in_array($n, $own[$u] ?? [], true)) return Http::response(['message' => 'Not Found'], 404);
        $st = &$S[$n];
        $isUrlfwd = str_contains($path, '/urlforwarding/');
        if ($rest === '' && !$isUrlfwd && $m === 'GET') return Http::response(dom($n, ['nameservers' => $st['ns'], 'contacts' => $st['contacts']]));
        if ($rest === '/records') {
            if ($m === 'GET') return Http::response(['records' => $st['records']]);
            $id = count($st['records']) + 100 + rand(1, 9999); $rec = ['id' => $id] + $body; $st['records'][] = $rec; return Http::response($rec);
        }
        if (preg_match('#^/records/(\d+)$#', $rest, $x)) {
            foreach ($st['records'] as $i => $rec) if ($rec['id'] == $x[1]) {
                if ($m === 'DELETE') { array_splice($st['records'], $i, 1); return Http::response(null, 204); }
                $st['records'][$i] = ['id' => (int) $x[1]] + $body; return Http::response($st['records'][$i]);
            }
            return Http::response([], 404);
        }
        if ($isUrlfwd) {
            if ($rest === '' && $m === 'GET') return Http::response(['urlForwarding' => $st['url']]);
            if (preg_match('#^/(\d+)$#', $rest, $x)) foreach ($st['url'] as $i => $f) if ($f['id'] == $x[1]) {
                if ($m === 'DELETE') { array_splice($st['url'], $i, 1); return Http::response(null, 204); }
                $st['url'][$i] = $body + $f; return Http::response($st['url'][$i]);
            }
            return Http::response([], 404);
        }
        if ($rest === '/url/forwarding' && $m === 'POST') { $f = ['id' => 500 + count($st['url'])] + $body; $st['url'][] = $f; return Http::response($f); }
        if ($rest === '/email/forwarding') {
            if ($m === 'GET') return Http::response(['emailForwarding' => $st['mail']]);
            $st['mail'][] = ['domainName' => $n] + $body; return Http::response($body);
        }
        if (preg_match('#^/email/forwarding/([a-z0-9._+-]+)$#', $rest, $x)) foreach ($st['mail'] as $i => $f) if ($f['emailBox'] === $x[1]) {
            if ($m === 'DELETE') { array_splice($st['mail'], $i, 1); return Http::response(null, 204); }
            $st['mail'][$i]['emailTo'] = $body['emailTo']; return Http::response($st['mail'][$i]);
        }
        if ($rest === '/vanity_nameservers') {
            if ($m === 'GET') return Http::response(['vanityNameservers' => $st['hosts']]);
            $h = ['domainName' => $n, 'hostname' => $body['hostname'] . '.' . $n, 'ips' => $body['ips']]; $st['hosts'][] = $h; return Http::response($h);
        }
        if (preg_match('#^/vanity_nameservers/([a-z0-9.-]+)$#', $rest, $x)) foreach ($st['hosts'] as $i => $h) if ($h['hostname'] === $x[1]) { $st['hosts'][$i]['ips'] = $body['ips']; return Http::response($st['hosts'][$i]); }
        if ($rest === ':setContacts') { $st['contacts'] = $body['contacts']; return Http::response(dom($n, ['contacts' => $st['contacts']])); }
        if ($rest === ':setNameservers') { $st['ns'] = $body['nameservers']; return Http::response(dom($n, ['nameservers' => $st['ns']])); }
        return Http::response([], 200);
    }];
}
function calls() { return Http::recorded()->map(fn ($p) => $p[0]->method() . ' ' . parse_url($p[0]->url(), PHP_URL_PATH) . ' @' . user($p[0]))->values()->all(); }
function sent($to, string $cls, ?callable $f = null): bool { return Notification::sent($to, $cls, $f)->isNotEmpty(); }
function fresh(): array { return ['records' => [
    ['id' => 1, 'domainName' => 'x', 'host' => '', 'type' => 'NS', 'answer' => 'ns1abc.name.com', 'ttl' => 300],
    ['id' => 2, 'domainName' => 'x', 'host' => '', 'type' => 'NS', 'answer' => 'ns2def.name.com', 'ttl' => 300],
    ['id' => 3, 'domainName' => 'x', 'host' => 'www', 'type' => 'A', 'answer' => '203.0.113.5', 'ttl' => 300],
], 'url' => [], 'mail' => [], 'hosts' => [], 'ns' => ['ns1abc.name.com', 'ns2def.name.com'],
    'contacts' => ['registrant' => contact('Reg'), 'admin' => contact('Adm'), 'tech' => contact('Tec'), 'billing' => contact('Bil')]]; }

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
    $clientA = Client::create(['name' => 'NC Mgr Client A TEST', 'phone' => '255700000601', 'email' => 'ncm-a@example.test', 'status' => 'active']);
    $clientB = Client::create(['name' => 'NC Mgr Client B TEST', 'phone' => '255700000602', 'email' => 'ncm-b@example.test', 'status' => 'active']);
    $mk = fn ($n, $c, $acc, $st = 'active') => Domain::create(['tenant_id' => $tenantA->id, 'client_id' => $c->id, 'name' => $n, 'status' => $st, 'expires_at' => '2031-03-04', 'auto_renew' => false,
        'meta' => ['unmanaged' => true, 'namecom' => ['account_id' => $acc->id, 'nameservers' => ['ns1abc.name.com', 'ns2def.name.com'], 'original_nameservers' => ['ns1abc.name.com', 'ns2def.name.com']]]]);
    $d1 = $mk('mgr-one-test.com', $clientA, $accA);
    $d2 = $mk('mgr-two-test.com', $clientA, $accB);
    $dOther = $mk('mgr-other-test.com', $clientB, $accA);
    $dPend = $mk('mgr-pend-test.com', $clientA, $accA, 'pending');
    $plain = Domain::create(['tenant_id' => $tenantA->id, 'client_id' => $clientA->id, 'name' => 'mgr-plain-test.com', 'status' => 'active', 'expires_at' => '2031-03-04', 'meta' => ['unmanaged' => true]]);
    $mkU = fn ($c, $role, $e) => ClientUser::create(['client_id' => $c->id, 'tenant_id' => $tenantA->id, 'name' => 'U ' . $e, 'email' => $e, 'password' => 'x-Secret-123', 'role' => $role, 'is_active' => true]);
    $uA = $mkU($clientA, 'admin', 'ncm-ua@example.test'); $uV = $mkU($clientA, 'viewer', 'ncm-uv@example.test'); $uB = $mkU($clientB, 'admin', 'ncm-ub@example.test');

    $own = ['owner' => ['mgr-one-test.com', 'mgr-other-test.com', 'mgr-pend-test.com'], 'second' => ['mgr-two-test.com']];
    $S = ['mgr-one-test.com' => fresh(), 'mgr-two-test.com' => fresh(), 'mgr-other-test.com' => fresh(), 'mgr-pend-test.com' => fresh()];
    $S['mgr-two-test.com']['ns'] = ['ns1.elsewhere.example.org', 'ns2.elsewhere.example.org'];
    $lim = fn () => DomainLog::whereIn('domain_id', [$d1->id, $d2->id])->where('action', 'like', 'dm_%')->delete();

    // ═════════ allow-list ═════════
    $allowed = [['GET', '/core/v1/domains/a.com/records'], ['POST', '/core/v1/domains/a.com/records'], ['PUT', '/core/v1/domains/a.com/records/12'], ['DELETE', '/core/v1/domains/a.com/records/12'],
        ['GET', '/core/v1/domains/a.com/email/forwarding'], ['POST', '/core/v1/domains/a.com/email/forwarding'], ['PUT', '/core/v1/domains/a.com/email/forwarding/info'], ['DELETE', '/core/v1/domains/a.com/email/forwarding/info'],
        ['GET', '/core/v1/urlforwarding/a.com'], ['POST', '/core/v1/domains/a.com/url/forwarding'], ['PATCH', '/core/v1/urlforwarding/a.com/7'], ['DELETE', '/core/v1/urlforwarding/a.com/7'],
        ['GET', '/core/v1/domains/a.com/vanity_nameservers'], ['POST', '/core/v1/domains/a.com/vanity_nameservers'], ['PUT', '/core/v1/domains/a.com/vanity_nameservers/ns1.a.com'],
        ['POST', '/core/v1/domains/a.com:setContacts'], ['GET', '/core/v1/domains/a.com'], ['POST', '/core/v1/domains/a.com:setNameservers']];
    foreach ($allowed as [$m, $p]) { try { NameComDriver::assertAllowed($m, $p); ok(true, "allowed $m $p"); } catch (NameComApiException) { ok(false, "allowed $m $p"); } }
    $refused = [['DELETE', '/core/v1/domains/a.com'], ['DELETE', '/core/v1/domains/a.com/records'], ['PUT', '/core/v1/domains/a.com/records'], ['DELETE', '/core/v1/domains/a.com/vanity_nameservers/ns1.a.com'],
        ['DELETE', '/core/v1/domains/a.com/url/forwarding/www'], ['PUT', '/core/v1/domains/a.com/url/forwarding/www'], ['GET', '/core/v1/domains/a.com/url/forwarding'], ['POST', '/core/v1/urlforwarding/a.com'],
        ['PATCH', '/core/v1/domains/a.com/records/1'], ['PUT', '/core/v1/domains/a.com/records/abc'], ['PUT', '/core/v1/domains/a.com/records/1/../x'], ['DELETE', '/core/v1/domains/a.com/records/1/extra'],
        ['DELETE', '/core/v1/domains/a.com/dnssec/x'], ['POST', '/core/v1/domains/a.com/dnssec'], ['GET', '/core/v1/domains/a.com/dnssec'],
        ['POST', '/core/v1/domains/a.com:renew'], ['POST', '/core/v1/transfers'], ['POST', '/core/v1/domains/a.com:purchasePrivacy'], ['POST', '/core/v1/domains/a.com:enableWhoisPrivacy'], ['POST', '/core/v1/domains/a.com:enableAutorenew'],
        ['POST', '/core/v1/domains'], ['GET', '/core/v1/domains/a.com:getPricing'], ['POST', '/core/v1/refund'], ['GET', '/core/v1/orders'], ['GET', '/core/v1/transfers'], ['PUT', '/core/v1/domains/a.com'], ['DELETE', '/core/v1/domains/a.com:setContacts'],
        ['GET', '/core/v1/domains/a.com:setContacts'], ['POST', '/core/v1/domains/a.com/records/5']];
    foreach ($refused as [$m, $p]) { try { NameComDriver::assertAllowed($m, $p); ok(false, "refused $m $p"); } catch (NameComApiException) { ok(true, "refused $m $p"); } }
    fk([]);
    try { (new NameComDriver($accA))->renew('a.com'); ok(false, 'renew refused'); } catch (\Throwable) { ok(hits() === 0, 'renew refused, no HTTP'); }

    // ═════════ static validation (no HTTP) ═════════
    fk([]);
    $bad = fn (callable $f) => (function () use ($f) { try { $f(); return false; } catch (\InvalidArgumentException) { return true; } })();
    ok($bad(fn () => M::validateRecord(['type' => 'NS', 'name' => '', 'target' => 'ns1.x.com'])), 'record: NS refused');
    ok($bad(fn () => M::validateRecord(['type' => 'CAA', 'name' => '', 'target' => 'x'])), 'record: unsupported type refused');
    ok($bad(fn () => M::validateRecord(['type' => 'A', 'name' => 'www', 'target' => 'not-an-ip'])), 'record: A needs IPv4');
    ok($bad(fn () => M::validateRecord(['type' => 'AAAA', 'name' => 'www', 'target' => '1.2.3.4'])), 'record: AAAA needs IPv6');
    ok($bad(fn () => M::validateRecord(['type' => 'CNAME', 'name' => '', 'target' => 'a.example.org'])), 'record: apex CNAME refused');
    ok($bad(fn () => M::validateRecord(['type' => 'A', 'name' => 'w w', 'target' => '1.2.3.4'])), 'record: bad host refused');
    ok($bad(fn () => M::validateRecord(['type' => 'A', 'name' => 'www', 'target' => '1.2.3.4', 'ttl_sec' => 60])), 'record: TTL < 300 refused');
    ok($bad(fn () => M::validateRecord(['type' => 'MX', 'name' => '', 'target' => 'mail.example.org'])), 'record: MX needs priority');
    ok($bad(fn () => M::validateRecord(['type' => 'SRV', 'name' => 'x', 'target' => 't.example.org', 'priority' => 1, 'weight' => 1, 'port' => 5, 'service' => 'sip', 'protocol' => 'icmp'])), 'record: SRV protocol checked');
    ok($bad(fn () => M::validateRecord(['type' => 'A', 'name' => 'www', 'target' => '203.0.113.5'], [['id' => 3, 'type' => 'A', 'name' => 'www', 'target' => '203.0.113.5']])), 'record: duplicate refused');
    ok($bad(fn () => M::validateRecord(['type' => 'CNAME', 'name' => 'www', 'target' => 'a.example.org'], [['id' => 3, 'type' => 'A', 'name' => 'www', 'target' => '1.1.1.1']])), 'record: CNAME conflict refused');
    [$b, $sh] = M::validateRecord(['type' => 'SRV', 'name' => 'phone', 'target' => 'Sip.Example.org.', 'priority' => 5, 'weight' => 1, 'port' => 5061, 'service' => '_sip', 'protocol' => 'TCP']);
    ok($b === ['type' => 'SRV', 'host' => '_sip._tcp.phone', 'answer' => '1 5061 sip.example.org', 'ttl' => 300, 'priority' => 5], 'record: SRV mapped to host/answer form');
    $back = M::mapRecord(['id' => 9, 'type' => 'SRV', 'host' => '_sip._tcp.phone', 'answer' => '1 5061 sip.example.org', 'priority' => 5, 'ttl' => 300]);
    ok($back['service'] === 'sip' && $back['protocol'] === 'tcp' && $back['name'] === 'phone' && $back['weight'] === 1 && $back['port'] === 5061 && $back['target'] === 'sip.example.org', 'record: SRV mapped back to shared shape');
    ok(M::mapRecord(['id' => 1, 'type' => 'NS', 'host' => '', 'answer' => 'ns1.name.com', 'ttl' => 300])['locked'] === true, 'record: NS shows locked');
    ok(M::dnsInUse(['ns1abc.name.com', 'ns2def.name.com']) && !M::dnsInUse(['ns1.linode.com', 'ns2.linode.com']) && !M::dnsInUse(['ns1.name.com', 'ns2.evil.example']) && !M::dnsInUse([]) && !M::dnsInUse(['ns1.name.com.evil.org']), 'dnsInUse logic');
    foreach (['http://localhost/x', 'http://127.0.0.1', 'https://10.0.0.5/a', 'http://192.168.1.1', 'http://169.254.169.254/latest', 'ftp://example.org', 'javascript:alert(1)', 'https://user:pw@example.org', 'http://[::1]/', 'http://intranet/x', 'http://router.local', 'http://2130706433/', 'https://mgr-one-test.com/x', 'https://sub.mgr-one-test.com', 'http://example.org:22/', 'https://ok.org/a b'] as $u) {
        ok($bad(fn () => M::validateForwardTarget($u, 'mgr-one-test.com')), "forward target refused: $u");
    }
    ok(M::validateForwardTarget('https://www.google.co.tz/path?q=1', 'mgr-one-test.com') === 'https://www.google.co.tz/path?q=1', 'forward target public https ok');
    ok($bad(fn () => M::validateEmailForward(['box' => '*', 'to' => 'a@gmail.com'], 'x.com')) && $bad(fn () => M::validateEmailForward(['box' => 'info', 'to' => 'a@x.com'], 'x.com')) && $bad(fn () => M::validateEmailForward(['box' => 'info', 'to' => 'a@localhost'], 'x.com'))
        && $bad(fn () => M::validateEmailForward(['box' => 'info', 'to' => 'a@gmail.com, b@gmail.com'], 'x.com')) && $bad(fn () => M::validateEmailForward(['box' => 'in fo', 'to' => 'a@gmail.com'], 'x.com')), 'email forward: wildcard / same-domain / internal / list refused');
    ok(M::validateEmailForward(['box' => 'Info@x.com', 'to' => 'Me@Gmail.com'], 'x.com') === ['box' => 'info', 'to' => 'me@gmail.com'], 'email forward normalised');
    ok($bad(fn () => M::validateHost('ns1', ['10.0.0.1'], 'x.com')) && $bad(fn () => M::validateHost('ns1', ['127.0.0.1'], 'x.com')) && $bad(fn () => M::validateHost('ns1', ['192.168.0.9'], 'x.com')) && $bad(fn () => M::validateHost('ns1', [], 'x.com'))
        && $bad(fn () => M::validateHost('ns1', ['::1'], 'x.com')) && $bad(fn () => M::validateHost('ns1.other.com', ['8.8.8.8'], 'x.com')) && $bad(fn () => M::validateHost('a.b', ['8.8.8.8'], 'x.com')) && $bad(fn () => M::validateHost('ns1', ['8.8.8.8', '8.8.4.4', '1.1.1.1', '1.0.0.1', '9.9.9.9'], 'x.com')), 'host: private/loopback/empty/foreign/too many refused');
    ok(M::validateHost('NS1.X.com', ['8.8.8.8', '2606:4700:4700::1111'], 'x.com') === ['label' => 'ns1', 'ips' => ['8.8.8.8', '2606:4700:4700::1111']], 'host: full name + public v4/v6 ok');
    ok($bad(fn () => M::validateContact('admin', ['first_name' => 'A'] + [])) && $bad(fn () => M::validateContact('admin', ['first_name' => 'A', 'last_name' => 'B', 'address1' => 'x', 'city' => 'c', 'state' => 's', 'zip' => '1', 'country' => 'TZA', 'email' => 'a@b.co', 'phone' => '+255712345678']))
        && $bad(fn () => M::validateContact('admin', ['first_name' => 'A', 'last_name' => 'B', 'address1' => 'x', 'city' => 'c', 'state' => 's', 'zip' => '1', 'country' => 'TZ', 'email' => 'nope', 'phone' => '+255712345678']))
        && $bad(fn () => M::validateContact('admin', ['first_name' => 'A', 'last_name' => 'B', 'address1' => 'x', 'city' => 'c', 'state' => 's', 'zip' => '1', 'country' => 'TZ', 'email' => 'a@b.co', 'phone' => '0712345678'])), 'contact: required / ISO-2 / email / E.164 enforced');
    ok(hits() === 0, 'validation refusals made no HTTP call');

    // ═════════ ownership / role / linked ═════════
    fk(fakeNc($own, $S));
    foreach (['dns', 'contacts', 'forwarding', 'hosts'] as $m) ok(pc($uB, $m, $d1)->getStatusCode() === 404, "other client -> 404 on $m");
    ok(pc($uB, 'recordStore', $d1, ['type' => 'A', 'name' => 'x', 'target' => '1.2.3.4'])->getStatusCode() === 404 && pc($uB, 'recordDestroy', $d1, [], '3')->getStatusCode() === 404 && pc($uB, 'hostStore', $d1, ['host' => 'ns1', 'ips' => ['8.8.8.8']])->getStatusCode() === 404, "other client writes -> 404");
    ok(pc($uA, 'dns', $plain)->getStatusCode() === 404 && pc($uA, 'recordStore', $plain, ['type' => 'A', 'name' => 'x', 'target' => '1.2.3.4'])->getStatusCode() === 404, 'non-linked domain -> 404');
    ok(pc($uA, 'dns', $dOther)->getStatusCode() === 404, "client A cannot reach client B's domain");
    ok(hits() === 0, 'ownership refusals made no HTTP call');
    $w = [['recordStore', ['type' => 'A', 'name' => 'x', 'target' => '1.2.3.4'], null], ['recordUpdate', ['type' => 'A', 'name' => 'www', 'target' => '1.2.3.4'], '3'], ['recordDestroy', [], '3'], ['useDefaultServers', ['confirm' => true], null],
        ['contactsUpdate', ['confirm' => true, 'contacts' => ['admin' => []]], null], ['urlStore', ['host' => 'www', 'target' => 'https://google.com', 'type' => 'permanent'], null], ['urlDestroy', [], '5'],
        ['emailStore', ['box' => 'a', 'to' => 'a@gmail.com'], null], ['emailDestroy', [], 'a'], ['hostStore', ['host' => 'ns1', 'ips' => ['8.8.8.8']], null], ['hostUpdate', ['ips' => ['8.8.8.8']], 'ns1.mgr-one-test.com']];
    foreach ($w as [$m, $b, $a]) ok(pc($uV, $m, $d1, $b, $a)->getStatusCode() === 403, "viewer -> 403 on $m");
    ok(pc($uA, 'recordStore', $dPend, ['type' => 'A', 'name' => 'x', 'target' => '1.2.3.4'])->getStatusCode() === 422 && hits() === 0, 'pending domain: writes refused');
    foreach (['dns', 'contacts', 'forwarding', 'hosts'] as $m) ok(pc($uV, $m, $d1)->getStatusCode() === 200, "viewer can read $m");
    ok(hits() > 0 && collect(calls())->every(fn ($c) => str_starts_with($c, 'GET ')), 'viewer reads only issued GETs');

    // ═════════ DNS ═════════
    fk(fakeNc($own, $S));
    $r = pc($uA, 'dns', $d1); $dj = j($r)['data'];
    ok($r->getStatusCode() === 200 && count($dj['records']) === 1 && $dj['in_use'] === true && !isset($dj['nameservers']) && $dj['max_records'] === 100, 'dns: list mapped, in_use true on their nameservers');
    ok(calls() === ['GET /core/v1/domains/mgr-one-test.com/records @owner', 'GET /core/v1/domains/mgr-one-test.com @owner'], 'dns list: GET records + GET domain on the domain account');
    fk(fakeNc($own, $S));
    $r = pc($uA, 'dns', $d2); $dj = j($r)['data'];
    ok($dj['in_use'] === false && collect(calls())->every(fn ($c) => str_ends_with($c, '@second')), 'dns: nameservers elsewhere -> in_use false; account B used for domain 2');
    // add
    $lim();
    fk(fakeNc($own, $S));
    $r = pc($uA, 'recordStore', $d1, ['type' => 'A', 'name' => 'blog', 'target' => '198.51.100.7', 'ttl_sec' => 600]);
    ok($r->getStatusCode() === 201 && j($r)['data']['name'] === 'blog' && j($r)['data']['target'] === '198.51.100.7', 'dns add: 201');
    ok(calls() === ['GET /core/v1/domains/mgr-one-test.com/records @owner', 'POST /core/v1/domains/mgr-one-test.com/records @owner'], 'dns add: list (dup check) then exactly one POST on right account');
    $post = Http::recorded()->last()[0];
    ok(json_decode($post->body(), true) === ['type' => 'A', 'host' => 'blog', 'answer' => '198.51.100.7', 'ttl' => 600], 'dns add: body uses registrar field names');
    $al = NameComAuditLog::where('action', 'dns.record_add')->latest('created_at')->first();
    ok($al && $al->target === 'mgr-one-test.com' && $al->request['by_portal_user'] === $uA->id && $al->request['type'] === 'A', 'dns add audited with portal user');
    ok(DomainLog::where('domain_id', $d1->id)->where('action', 'dm_dns_record_added')->count() === 1, 'dns add: neutral DomainLog row');
    $show = j(app(PortalDomainController::class)->show(req(Request::create('/x'), $uA), $d1));
    ok(collect($show['data']['activity'])->pluck('action')->contains('DNS record added'), 'client activity list shows neutral label "DNS record added"');
    // edit
    $rid = collect($S['mgr-one-test.com']['records'])->firstWhere('host', 'blog')['id'];
    fk(fakeNc($own, $S));
    $r = pc($uA, 'recordUpdate', $d1, ['type' => 'A', 'name' => 'blog', 'target' => '198.51.100.8', 'ttl_sec' => 3600], (string) $rid);
    ok($r->getStatusCode() === 200 && end($S['mgr-one-test.com']['records'])['answer'] === '198.51.100.8', 'dns edit ok');
    ok(calls() === ['GET /core/v1/domains/mgr-one-test.com/records @owner', "PUT /core/v1/domains/mgr-one-test.com/records/$rid @owner"], 'dns edit: exactly one PUT');
    fk(fakeNc($own, $S));
    ok(pc($uA, 'recordUpdate', $d1, ['type' => 'A', 'name' => 'www', 'target' => '1.2.3.4'], '1')->getStatusCode() === 422 && collect(calls())->every(fn ($c) => str_starts_with($c, 'GET ')), 'dns edit: NS record cannot be edited (no write)');
    fk(fakeNc($own, $S));
    ok(pc($uA, 'recordUpdate', $d1, ['type' => 'A', 'name' => 'x', 'target' => '1.2.3.4'], '99999')->getStatusCode() === 422 && collect(calls())->every(fn ($c) => str_starts_with($c, 'GET ')), 'dns edit: unknown record -> clean 422, no write');
    // validation refusal: no HTTP
    fk(fakeNc($own, $S));
    ok(pc($uA, 'recordStore', $d1, ['type' => 'A', 'name' => 'x', 'target' => 'bad'])->getStatusCode() === 422, 'dns add: invalid -> 422');
    ok(collect(calls())->every(fn ($c) => str_starts_with($c, 'GET ')), 'dns add invalid: no write issued');
    // delete
    fk(fakeNc($own, $S));
    $r = pc($uA, 'recordDestroy', $d1, [], (string) $rid);
    ok($r->getStatusCode() === 200 && !collect($S['mgr-one-test.com']['records'])->contains('id', $rid), 'dns delete ok');
    ok(calls() === ['GET /core/v1/domains/mgr-one-test.com/records @owner', "DELETE /core/v1/domains/mgr-one-test.com/records/$rid @owner"], 'dns delete: exactly one DELETE of one record');
    fk(fakeNc($own, $S));
    ok(pc($uA, 'recordDestroy', $d1, [], '1')->getStatusCode() === 422 && collect(calls())->every(fn ($c) => str_starts_with($c, 'GET ')), 'dns delete: NS record refused, no DELETE');
    // record limit
    $lim();
    $S['mgr-one-test.com']['records'] = array_merge($S['mgr-one-test.com']['records'], array_map(fn ($i) => ['id' => 1000 + $i, 'host' => "h$i", 'type' => 'A', 'answer' => '203.0.113.9', 'ttl' => 300], range(1, 100)));
    fk(fakeNc($own, $S));
    ok(pc($uA, 'recordStore', $d1, ['type' => 'A', 'name' => 'over', 'target' => '1.2.3.4'])->getStatusCode() === 422 && collect(calls())->every(fn ($c) => str_starts_with($c, 'GET ')), 'dns: record limit (100) enforced, no POST');
    $S['mgr-one-test.com']['records'] = fresh()['records'];
    // write rate limit 40/hour
    $lim();
    for ($i = 0; $i < 40; $i++) DomainLog::create(['tenant_id' => $tenantA->id, 'domain_id' => $d1->id, 'action' => 'dm_dns_record_added', 'request' => [], 'status' => 'success']);
    fk(fakeNc($own, $S));
    $r = pc($uA, 'recordStore', $d1, ['type' => 'A', 'name' => 'lim', 'target' => '1.2.3.4']);
    ok($r->getStatusCode() === 422 && str_contains(j($r)['message'], 'limit of 40') && hits() === 0, 'dns: 41st change in an hour refused, no HTTP');
    $lim();
    // use default servers
    ok(pc($uA, 'useDefaultServers', $d2, [])->getStatusCode() === 422, 'use our DNS: needs explicit confirm');
    fk(fakeNc($own, $S)); $before = calls();
    $r = pc($uA, 'useDefaultServers', $d2, ['confirm' => true]);
    ok($r->getStatusCode() === 200 && j($r)['data'] === ['changed' => true] && $S['mgr-two-test.com']['ns'] === ['ns1abc.name.com', 'ns2def.name.com'], 'use our DNS: switches to the zone\'s own servers (from apex NS records)');
    ok(collect(calls())->contains('POST /core/v1/domains/mgr-two-test.com:setNameservers @second') && collect(calls())->filter(fn ($c) => str_starts_with($c, 'POST '))->count() === 1, 'use our DNS: exactly one setNameservers on domain account');
    ok(DomainLog::where('domain_id', $d2->id)->where('action', 'namecom_nameservers_changed')->count() === 1, 'use our DNS: goes through the guarded nameserver update (logged/limited)');
    // and that reading never changes nameservers silently
    fk(fakeNc($own, $S)); $S['mgr-two-test.com']['ns'] = ['ns1.elsewhere.example.org', 'ns2.elsewhere.example.org'];
    pc($uA, 'dns', $d2); pc($uA, 'forwarding', $d2); pc($uA, 'hosts', $d2);
    ok(collect(calls())->every(fn ($c) => str_starts_with($c, 'GET ')) && $S['mgr-two-test.com']['ns'][0] === 'ns1.elsewhere.example.org', 'reads never change nameservers');

    // ═════════ contacts ═════════
    Notification::fake(); $lim();
    fk(fakeNc($own, $S));
    $r = pc($uA, 'contacts', $d1);
    ok($r->getStatusCode() === 200 && j($r)['data']['contacts']['registrant']['first_name'] === 'Reg' && array_keys(j($r)['data']['contacts']) === ['registrant', 'admin', 'tech', 'billing'], 'contacts: read maps four roles');
    ok(calls() === ['GET /core/v1/domains/mgr-one-test.com @owner'], 'contacts read: one GET domain');
    $new = ['first_name' => 'Amina', 'last_name' => 'Mushi', 'company' => '', 'address1' => '9 New Rd', 'address2' => '', 'city' => 'Arusha', 'state' => 'AR', 'zip' => '23100', 'country' => 'tz', 'email' => 'amina@example.test', 'phone' => '+255755000111', 'fax' => ''];
    fk(fakeNc($own, $S));
    ok(pc($uA, 'contactsUpdate', $d1, ['contacts' => ['registrant' => $new]])->getStatusCode() === 422 && hits() === 0, 'contacts: needs explicit confirmation, no HTTP');
    ok(pc($uA, 'contactsUpdate', $d1, ['confirm' => true, 'contacts' => ['registrant' => ['phone' => '123'] + $new]])->getStatusCode() === 422 && hits() === 0, 'contacts: invalid phone -> 422, no HTTP');
    ok(pc($uA, 'contactsUpdate', $d1, ['confirm' => true, 'contacts' => ['owner' => $new]])->getStatusCode() === 422 && hits() === 0, 'contacts: unknown role refused, no HTTP');
    $r = pc($uA, 'contactsUpdate', $d1, ['confirm' => true, 'contacts' => ['registrant' => $new]]);
    ok($r->getStatusCode() === 200 && j($r)['data']['changed'] === ['registrant'], 'contacts: saved, only registrant changed');
    ok(calls() === ['GET /core/v1/domains/mgr-one-test.com @owner', 'POST /core/v1/domains/mgr-one-test.com:setContacts @owner'], 'contacts: one GET then exactly one POST :setContacts');
    $sent = json_decode(Http::recorded()->last()[0]->body(), true)['contacts'];
    ok(array_keys($sent) === ['registrant', 'admin', 'tech', 'billing'] && $sent['registrant']['firstName'] === 'Amina' && $sent['registrant']['country'] === 'TZ' && $sent['admin']['firstName'] === 'Adm' && !isset($sent['registrant']['isVerified']) && !array_key_exists('fax', $sent['registrant']), 'contacts: all four roles sent complete, edited merged, read-only flags dropped');
    ok(sent($staffA, DomainManagerActivityNotification::class, fn ($n) => $n->what === 'contacts' && $n->byClient === true), 'contacts: staff notified');
    $al = NameComAuditLog::where('action', 'contacts.set')->latest('created_at')->first();
    ok($al && $al->request['roles'] === ['registrant'] && !str_contains(json_encode($al->request), 'Amina') && !str_contains(json_encode($al->request), 'amina@'), 'contacts audit: roles only, no personal data');
    ok(!str_contains(json_encode(DomainLog::where('domain_id', $d1->id)->get()), 'Amina'), 'contacts domain log: no personal data');
    fk(fakeNc($own, $S));
    $r = pc($uA, 'contactsUpdate', $d1, ['confirm' => true, 'contacts' => ['registrant' => $new]]);
    ok($r->getStatusCode() === 200 && j($r)['data']['changed'] === [] && calls() === ['GET /core/v1/domains/mgr-one-test.com @owner'], 'contacts: unchanged values -> no write');
    for ($i = 0; $i < 3; $i++) DomainLog::create(['tenant_id' => $tenantA->id, 'domain_id' => $d1->id, 'action' => 'dm_contacts_changed', 'request' => [], 'status' => 'success']);
    fk(fakeNc($own, $S));
    $r = pc($uA, 'contactsUpdate', $d1, ['confirm' => true, 'contacts' => ['admin' => ['first_name' => 'Zed'] + $new]]);
    ok($r->getStatusCode() === 422 && hits() === 0, 'contacts: 4th change in 24h refused, no HTTP');
    $lim();
    fk(fakeNc($own, $S));
    ok(pc($uA, 'contactsUpdate', $d2, ['confirm' => true, 'contacts' => ['tech' => ['first_name' => 'Tee'] + $new]])->getStatusCode() === 200 && collect(calls())->every(fn ($c) => str_ends_with($c, '@second')), 'contacts: per-domain account (B)');
    $lim();

    // ═════════ forwarding ═════════
    Notification::fake();
    fk(fakeNc($own, $S));
    $r = pc($uA, 'urlStore', $d1, ['host' => 'www', 'target' => 'https://www.example.org/landing', 'type' => 'masked', 'title' => '<b>My Site</b>']);
    ok($r->getStatusCode() === 201 && j($r)['data']['type'] === 'masked' && j($r)['data']['target'] === 'https://www.example.org/landing', 'url fwd add: 201');
    ok(calls() === ['GET /core/v1/urlforwarding/mgr-one-test.com @owner', 'POST /core/v1/domains/mgr-one-test.com/url/forwarding @owner'], 'url fwd add: list then exactly one POST');
    ok(json_decode(Http::recorded()->last()[0]->body(), true) === ['host' => 'www', 'forwardsTo' => 'https://www.example.org/landing', 'type' => 'masked', 'title' => 'My Site'], 'url fwd add: body mapped, title stripped of tags');
    ok(sent($staffA, DomainManagerActivityNotification::class, fn ($n) => $n->what === 'url_forward'), 'url fwd: staff notified (external target)');
    fk(fakeNc($own, $S));
    ok(pc($uA, 'urlStore', $d1, ['host' => 'www', 'target' => 'https://other.org', 'type' => 'permanent'])->getStatusCode() === 422 && collect(calls())->every(fn ($c) => str_starts_with($c, 'GET ')), 'url fwd: same host twice refused');
    foreach (['http://127.0.0.1/', 'http://localhost', 'https://192.168.0.1/x', 'file:///etc/passwd', 'https://mgr-one-test.com'] as $u) {
        fk(fakeNc($own, $S));
        ok(pc($uA, 'urlStore', $d1, ['host' => 'app', 'target' => $u, 'type' => 'permanent'])->getStatusCode() === 422 && hits() === 0, "url fwd abuse guard: $u -> 422, no HTTP");
    }
    $fid = (string) $S['mgr-one-test.com']['url'][0]['id'];
    fk(fakeNc($own, $S));
    $r = pc($uA, 'urlUpdate', $d1, ['target' => 'https://new.example.net', 'type' => 'temporary'], $fid);
    ok($r->getStatusCode() === 200 && j($r)['data']['type'] === 'temporary', 'url fwd edit ok');
    ok(calls() === ['GET /core/v1/urlforwarding/mgr-one-test.com @owner', "PATCH /core/v1/urlforwarding/mgr-one-test.com/$fid @owner"], 'url fwd edit: exactly one PATCH by id');
    fk(fakeNc($own, $S));
    ok(pc($uA, 'urlUpdate', $d1, ['target' => 'http://127.0.0.1'], $fid)->getStatusCode() === 422 && collect(calls())->every(fn ($c) => str_starts_with($c, 'GET ')), 'url fwd edit: internal target refused');
    fk(fakeNc($own, $S));
    $r = pc($uA, 'urlDestroy', $d1, [], $fid);
    ok($r->getStatusCode() === 200 && $S['mgr-one-test.com']['url'] === [] && calls()[1] === "DELETE /core/v1/urlforwarding/mgr-one-test.com/$fid @owner", 'url fwd delete: one DELETE by id');
    // limit of 20
    $S['mgr-one-test.com']['url'] = array_map(fn ($i) => ['id' => 700 + $i, 'host' => "s$i", 'forwardsTo' => 'https://a.org', 'type' => 'redirect'], range(1, 20));
    fk(fakeNc($own, $S));
    ok(pc($uA, 'urlStore', $d1, ['host' => 'extra', 'target' => 'https://a.org', 'type' => 'permanent'])->getStatusCode() === 422 && collect(calls())->every(fn ($c) => str_starts_with($c, 'GET ')), 'url fwd: max 20 enforced');
    $S['mgr-one-test.com']['url'] = []; $lim();
    // email
    fk(fakeNc($own, $S));
    $r = pc($uA, 'emailStore', $d1, ['box' => 'Info', 'to' => 'Owner@Gmail.com']);
    ok($r->getStatusCode() === 201 && j($r)['data']['address'] === 'info@mgr-one-test.com', 'email fwd add: 201');
    ok(calls() === ['GET /core/v1/domains/mgr-one-test.com/email/forwarding @owner', 'POST /core/v1/domains/mgr-one-test.com/email/forwarding @owner'], 'email fwd add: list then exactly one POST');
    ok(json_decode(Http::recorded()->last()[0]->body(), true) === ['emailBox' => 'info', 'emailTo' => 'owner@gmail.com'], 'email fwd add: body mapped');
    ok(sent($staffA, DomainManagerActivityNotification::class, fn ($n) => $n->what === 'email_forward'), 'email fwd: staff notified');
    foreach ([['box' => '*', 'to' => 'a@gmail.com'], ['box' => 'x', 'to' => 'a@mgr-one-test.com'], ['box' => 'x', 'to' => 'a@localhost'], ['box' => 'x', 'to' => 'nope'], ['box' => 'info', 'to' => 'z@gmail.com']] as $b) {
        fk(fakeNc($own, $S));
        $rr = pc($uA, 'emailStore', $d1, $b);
        ok($rr->getStatusCode() === 422 && collect(calls())->every(fn ($c) => str_starts_with($c, 'GET ')), 'email fwd refused: ' . json_encode($b) . ', no write');
    }
    fk(fakeNc($own, $S));
    $r = pc($uA, 'emailUpdate', $d1, ['to' => 'new@yahoo.com'], 'info');
    ok($r->getStatusCode() === 200 && calls()[1] === 'PUT /core/v1/domains/mgr-one-test.com/email/forwarding/info @owner', 'email fwd edit: one PUT');
    fk(fakeNc($own, $S));
    $r = pc($uA, 'emailDestroy', $d1, [], 'info');
    ok($r->getStatusCode() === 200 && $S['mgr-one-test.com']['mail'] === [] && calls()[1] === 'DELETE /core/v1/domains/mgr-one-test.com/email/forwarding/info @owner', 'email fwd delete: one DELETE');
    ok(pc($uA, 'emailDestroy', $d1, [], '../etc')->getStatusCode() === 404, 'email fwd: bad box in path -> 404');
    $S['mgr-one-test.com']['mail'] = array_map(fn ($i) => ['emailBox' => "b$i", 'emailTo' => 'a@gmail.com'], range(1, 20));
    fk(fakeNc($own, $S));
    ok(pc($uA, 'emailStore', $d1, ['box' => 'extra', 'to' => 'a@gmail.com'])->getStatusCode() === 422 && collect(calls())->every(fn ($c) => str_starts_with($c, 'GET ')), 'email fwd: max 20 enforced');
    $S['mail'] = []; $S['mgr-one-test.com']['mail'] = []; $lim();
    fk(fakeNc($own, $S));
    $r = pc($uA, 'forwarding', $d1);
    ok($r->getStatusCode() === 200 && j($r)['data']['url'] === [] && j($r)['data']['email'] === [] && j($r)['data']['max'] === 20, 'forwarding list ok');

    // ═════════ hosts (glue) ═════════
    Notification::fake();
    fk(fakeNc($own, $S));
    $r = pc($uA, 'hostStore', $d1, ['host' => 'ns1.mgr-one-test.com', 'ips' => ['203.0.113.10', '2606:4700:4700::1111']]);
    ok($r->getStatusCode() === 201 && j($r)['data']['hostname'] === 'ns1.mgr-one-test.com', 'host add: 201');
    ok(calls() === ['GET /core/v1/domains/mgr-one-test.com/vanity_nameservers @owner', 'POST /core/v1/domains/mgr-one-test.com/vanity_nameservers @owner'], 'host add: list then exactly one POST');
    ok(json_decode(Http::recorded()->last()[0]->body(), true) === ['hostname' => 'ns1', 'ips' => ['203.0.113.10', '2606:4700:4700::1111']], 'host add: label-only hostname sent');
    ok(sent($staffA, DomainManagerActivityNotification::class, fn ($n) => $n->what === 'host'), 'host: staff notified');
    foreach ([['host' => 'ns2', 'ips' => ['10.1.1.1']], ['host' => 'ns2', 'ips' => ['127.0.0.1']], ['host' => 'ns.evil.com', 'ips' => ['8.8.8.8']], ['host' => 'ns2', 'ips' => []]] as $b) {
        fk(fakeNc($own, $S));
        ok(pc($uA, 'hostStore', $d1, $b)->getStatusCode() === 422 && hits() === 0, 'host refused: ' . json_encode($b) . ', no HTTP');
    }
    fk(fakeNc($own, $S));
    $r = pc($uA, 'hostUpdate', $d1, ['ips' => ['198.51.100.44']], 'ns1.mgr-one-test.com');
    ok($r->getStatusCode() === 200 && calls()[1] === 'PUT /core/v1/domains/mgr-one-test.com/vanity_nameservers/ns1.mgr-one-test.com @owner', 'host edit: one PUT');
    fk(fakeNc($own, $S));
    ok(pc($uA, 'hostUpdate', $d1, ['ips' => ['198.51.100.44']], 'ns9.mgr-one-test.com')->getStatusCode() === 422 && collect(calls())->every(fn ($c) => str_starts_with($c, 'GET ')), 'host edit: unknown host refused, no write');
    $S['mgr-one-test.com']['hosts'] = array_map(fn ($i) => ['hostname' => "h$i.mgr-one-test.com", 'ips' => ['8.8.8.8']], range(1, 10));
    fk(fakeNc($own, $S));
    ok(pc($uA, 'hostStore', $d1, ['host' => 'extra', 'ips' => ['8.8.8.8']])->getStatusCode() === 422 && collect(calls())->every(fn ($c) => str_starts_with($c, 'GET ')), 'host: max 10 enforced');
    $S['mgr-one-test.com']['hosts'] = []; $lim();

    // ═════════ upstream failures -> generic ═════════
    foreach ([400, 403, 404, 409, 423, 429, 500, 503] as $code) {
        fk(fakeNc($own, $S, $code));
        $r = pc($uA, 'recordStore', $d1, ['type' => 'A', 'name' => 'e' . $code, 'target' => '1.2.3.4']);
        $g = pc($uA, 'dns', $d1);
        ok($r->getStatusCode() === 422 && $g->getStatusCode() === 422 && !str_contains($r->getContent() . $g->getContent(), 'SECRET-INTERNAL'), "upstream $code -> generic 422 (write + read)");
    }
    ok(DomainLog::where('domain_id', $d1->id)->where('action', 'like', 'dm_%')->where('status', '!=', 'success')->count() === 0 && DomainLog::where('domain_id', $d1->id)->where('action', 'dm_dns_record_added')->count() === 0, 'failed writes are not logged as successes');
    // account not connected -> generic, not the "connect your account" staff text
    $accA->update(['status' => 'invalid']);
    fk(fakeNc($own, $S));
    $r = pc($uA, 'dns', $d1);
    ok($r->getStatusCode() === 422 && hits() === 0 && !preg_match('/api|credential|token|name\.?com/i', $r->getContent()), 'unusable account -> generic message, no HTTP');
    $accA->update(['status' => 'active']);

    // ═════════ tenant isolation ═════════
    $sB = User::withoutGlobalScopes()->where('tenant_id', $tenantB->id)->first();
    try { app(\App\Services\Registrar\DomainRegistrarManager::class)->namecomFor($tenantB->id, $accA->id); ok(false, 'tenant B cannot use tenant A account'); }
    catch (\App\Exceptions\RegistrarApiException) { ok(true, 'tenant B cannot use tenant A account'); }
    $cuB = ClientUser::create(['client_id' => Client::withoutGlobalScopes()->where('tenant_id', $tenantB->id)->value('id') ?? $clientB->id, 'tenant_id' => $tenantB->id, 'name' => 'TB', 'email' => 'ncm-tb@example.test', 'password' => 'x-Secret-123', 'role' => 'admin', 'is_active' => true]);
    ok(pc($cuB, 'dns', $d1)->getStatusCode() === 404 && pc($cuB, 'recordStore', $d1, ['type' => 'A', 'name' => 'x', 'target' => '1.2.3.4'])->getStatusCode() === 404, 'client of tenant B cannot reach tenant A domain');

    // ═════════ routes ═════════
    $routes = collect(app('router')->getRoutes())->filter(fn ($r) => str_starts_with($r->uri(), 'api/portal/domains/{domain}/') && preg_match('#/(dns|contacts|forwarding|hosts)(/|$)#', $r->uri()));
    ok($routes->count() === 17, 'manager routes registered (17)');
    $buckets = $routes->map(fn ($r) => collect($r->gatherMiddleware())->first(fn ($m) => str_starts_with($m, 'throttle:')));
    ok($buckets->every(fn ($b) => substr_count((string) $b, ',') === 2) && $buckets->unique()->count() === $routes->count(), 'every manager route has its OWN named throttle bucket');
    ok(!preg_match('/name\.?com|namecom/i', $routes->map(fn ($r) => $r->uri())->implode(' ')), 'portal manager route paths are neutral');

    // ═════════ neutrality over every portal response ═════════
    $body = implode("\n", $PORTAL);
    ok(count($PORTAL) > 90, 'neutrality corpus collected (' . count($PORTAL) . ' responses, success + error)');
    preg_match('/.{30}(name\.?com|namecom|usd|supplier|\$\d|SECRET-INTERNAL).{30}/i', $body, $mm); if ($mm) echo 'MATCH: ' . $mm[0] . "\n";
    ok(!preg_match('/name\.?com|namecom|usd|supplier|\$\d|SECRET-INTERNAL/i', $body), 'no supplier/USD/internal wording in ANY portal response');
    ok(!preg_match('/"(provider|registrar|account|account_id|account_label|namecom|token|username)"/i', $body), 'no provider/account keys in portal JSON');
    ok(!str_contains($body, TOK_A) && !str_contains($body, TOK_B) && !str_contains(implode("\n", $logged), TOK_A) && !str_contains(implode("\n", $logged), TOK_B), 'tokens never in responses or logs');
    $an = new DomainManagerActivityNotification($d1, 'contacts', true);
    ok(!str_contains(json_encode([$an->toArray($staffA), $an->toFcm($staffA)]), 'Amina'), 'staff notification carries no personal data');
    $acts = collect(j(app(PortalDomainController::class)->show(req(Request::create('/x'), $uA), $d1))['data']['activity'])->pluck('action')->implode('|');
    ok(!preg_match('/name\.?com|namecom|dm_/i', $acts), 'client activity labels neutral (no dm_ / supplier)');
    $dl = DomainLog::where('domain_id', $d1->id)->where('action', 'like', 'dm_%')->pluck('action')->unique()->all();
    ok(collect($dl)->every(fn ($a) => M::activityLabel($a) !== 'Domain updated'), 'every dm_ action has a specific neutral label');
} catch (\Throwable $e) {
    $fail++; echo "EXCEPTION: " . $e->getMessage() . "\n" . $e->getFile() . ':' . $e->getLine() . "\n";
} finally {
    DB::rollBack();
}
echo $fail ? "\n$fail FAILED\n" : "\nALL PASSED\n";
exit($fail ? 1 : 0);
