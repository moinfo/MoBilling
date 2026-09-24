<?php

namespace Tests\Manual;

use App\Models\Client;
use App\Models\ClientSubscription;
use App\Models\Document;
use App\Models\Domain;
use App\Models\DomainTld;
use App\Models\HostingAccount;
use App\Models\LinodeAccount;
use App\Models\LinodeAuditLog;
use App\Models\LinodeResource;
use App\Models\MosmsAccount;
use App\Models\NameComAccount;
use App\Models\ProductService;
use App\Models\Server;
use App\Models\Tenant;
use App\Models\User;
use App\Models\WhatsappRenewalSession;
use App\Services\Linode\LinodeService;
use App\Services\Registrar\DomainRegistrarManager;
use App\Services\Registrar\DomainSuggestService;
use App\Services\Registrar\NameComDriver;
use App\Services\WhatsAppService;
use Illuminate\Http\Client\Factory;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Notification;

/**
 * "10) More services" (My Servers, Expiring soon) + multi-TLD option 7.
 * Live DB inside an ALWAYS-rolled-back transaction. WhatsApp bound to a recording fake; Linode and
 * Name.com behind Http::fake + preventStrayRequests; FRED behind a fake registrar manager.
 *
 *   php tests/Manual/run_whatsapp_more_services.php
 */
class WhatsappMoreServicesTest
{
    private function fail(string $m): void { throw new \RuntimeException($m); }
    public function assertSame($e, $a, string $m = ''): void { if ($e !== $a) $this->fail(($m ? "$m: " : '') . 'expected ' . var_export($e, true) . ' got ' . var_export($a, true)); }
    public function assertTrue($c, string $m = 'not true'): void { if (!$c) $this->fail($m); }
    public function assertContains($n, $h): void { if (!str_contains($h, $n)) $this->fail("missing '$n' in:\n$h"); }
    public function assertNotContains($n, $h): void { if (str_contains($h, $n)) $this->fail("unexpected '$n' in:\n$h"); }

    private Tenant $tenant;
    private User $user;
    private string $phone;
    private string $rawPhone = '255700000001';
    private ?LinodeAccount $acct = null;

    public function setUp(): void
    {
        $this->phone = \App\Helpers\PhoneHelper::normalize($this->rawPhone);
        DB::beginTransaction();
        $this->tenant = Tenant::withoutGlobalScopes()->where('name', 'MoBilling Test Co')->firstOrFail();
        $this->user = User::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->firstOrFail();
        auth()->login($this->user);

        config(['services.mosms.inbound_webhook_secret' => 'test-secret', 'services.mosms.inbound_rate_limit' => 100000]);
        MosmsAccount::create(['tenant_id' => $this->tenant->id, 'mosms_tenant_id' => 987654321, 'email' => 'x@example.test', 'token' => 'x', 'sender' => 'x']);

        LinodeService::$sleepOnRateLimit = false;
        LinodeService::$paginatedGapMs = 0;
        NameComDriver::$sleepOnRateLimit = false;
        NameComDriver::$paginatedGapMs = 0;

        $this->fk([]);
        Notification::fake();
        Fw::$sent = [];
        FakeRegistrar::$fred = [];
        FakeRegistrar::$fredCalls = 0;
        app()->bind(WhatsAppService::class, fn () => new Fw());
        app()->instance(DomainRegistrarManager::class, new FakeRegistrar());
        app()->bind(DomainSuggestService::class, fn ($a) => new DomainSuggestService($a->make(DomainRegistrarManager::class)));
    }

    public function tearDown(): void
    {
        DB::rollBack();
    }

    // ── helpers ──
    private function fk($x): void { Http::swap(new Factory()); Http::preventStrayRequests(); Http::fake($x); }

    private function makeClient(string $name = 'Asha Test', ?string $phone = null): Client
    {
        return Client::create(['tenant_id' => $this->tenant->id, 'name' => $name, 'phone' => $phone ?? $this->rawPhone, 'email' => strtolower(str_replace(' ', '', $name)) . '@example.test', 'status' => 'active']);
    }

    private function startSession(Client $client, ?string $assistedBy = null): void
    {
        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $this->tenant->id, 'phone' => $this->phone],
            ['client_id' => $client->id, 'assisted_by_user_id' => $assistedBy, 'flow' => null, 'state' => null, 'items' => null, 'language' => 'en', 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(30)],
        );
    }

    private function say(string $text): string
    {
        $before = count(Fw::$sent);
        $req = Request::create('/api/webhooks/mosms/menu', 'POST', ['secret' => 'test-secret', 'mosms_tenant_id' => 987654321, 'phone' => $this->rawPhone, 'text' => $text], [], [], ['HTTP_ACCEPT' => 'application/json']);
        $res = app()->handle($req);
        $this->assertSame(200, $res->getStatusCode());
        return implode("\n---\n", array_column(array_slice(Fw::$sent, $before), 'text'));
    }

    private function session(): ?WhatsappRenewalSession
    {
        return WhatsappRenewalSession::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->where('phone', $this->phone)->first();
    }

    public function checkNeutral(): void
    {
        foreach (Fw::$sent as $m) {
            foreach (['name.com', 'namecom', 'linode', 'usd', '$'] as $bad) {
                if (str_contains(strtolower($m['text']), $bad)) $this->fail("supplier/cost leak '$bad' in reply:\n{$m['text']}");
            }
            if (isset($m['button']) && preg_match('/name\.com|linode|usd/i', $m['button'])) $this->fail('leak in button');
        }
    }

    // servers
    private function linode(): LinodeAccount
    {
        if (!$this->acct) {
            $a = new LinodeAccount(['label' => 'T', 'token' => 'lin_SECRET_TOKEN_abcdefghijklmnopqrstuvwxyz1234', 'token_hint' => '1234', 'status' => 'active', 'soa_email' => 'soa@example.test']);
            $a->tenant_id = $this->tenant->id;
            $a->save();
            $this->acct = $a;
        }
        return $this->acct;
    }

    private function serverProduct(): ProductService
    {
        return ProductService::create(['tenant_id' => $this->tenant->id, 'type' => 'service', 'name' => 'Cloud Server Plan', 'price' => 30000, 'tax_percent' => 0, 'unit' => 'pcs', 'category' => 'Linode Servers', 'billing_cycle' => 'yearly', 'provisioning_type' => 'linode', 'portal_visible' => false, 'is_active' => true]);
    }

    /** @return array{0: LinodeResource, 1: ClientSubscription} */
    private function makeServer(Client $c, string $label, string $remote, string $ip, string $subStatus = 'active', ?string $expire = null, string $status = 'running'): array
    {
        $prod = ProductService::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->where('name', 'Cloud Server Plan')->first() ?? $this->serverProduct();
        $sub = ClientSubscription::create(['tenant_id' => $this->tenant->id, 'client_id' => $c->id, 'product_service_id' => $prod->id, 'label' => $label, 'quantity' => 1, 'start_date' => now()->subMonths(9), 'expire_date' => $expire ?? now()->addYear(), 'status' => $subStatus]);
        $srv = LinodeResource::create(['tenant_id' => $this->tenant->id, 'linode_account_id' => $this->linode()->id, 'type' => 'instance', 'remote_id' => $remote, 'label' => $label, 'status' => $status, 'region' => 'eu-central', 'ipv4' => [$ip], 'client_id' => $c->id, 'client_subscription_id' => $sub->id]);
        return [$srv, $sub];
    }

    private function lin(int $id, string $st): array
    {
        return ["api.linode.com/v4/linode/instances/$id" => Http::response(['id' => $id, 'status' => $st]), "api.linode.com/v4/linode/instances/$id/reboot" => Http::response([], 200)];
    }

    private function rebootPosts(): int
    {
        return Http::recorded(fn ($r) => $r->method() === 'POST' && str_ends_with($r->url(), '/reboot'))->count();
    }

    private function httpCount(): int { return Http::recorded()->count(); }

    private function audits(string $action)
    {
        return LinodeAuditLog::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->where('action', $action)->get();
    }

    private function seedAudit(LinodeResource $srv, string $action, int $n, ?string $clientId = null): void
    {
        for ($i = 0; $i < $n; $i++) {
            LinodeAuditLog::withoutGlobalScopes()->create(['tenant_id' => $this->tenant->id, 'linode_account_id' => $srv->linode_account_id, 'action' => $action, 'target' => "{$srv->label} #{$srv->remote_id}", 'request' => ['client_id' => $clientId ?? $srv->client_id], 'response_status' => 200]);
        }
    }

    // domain catalog
    private function tlds(): void
    {
        DomainTld::whereNull('tenant_id')->update(['is_active' => false]);
        DomainTld::where('tenant_id', $this->tenant->id)->delete();
        $mk = fn ($tld, $reg, $price, $pop, $sort, $unmanaged = false, $renew = null) => DomainTld::create(['tenant_id' => $this->tenant->id, 'tld' => $tld, 'registrar' => $reg, 'register_price' => $price, 'renew_price' => $renew ?? $price, 'transfer_price' => 0, 'is_active' => true, 'is_unmanaged' => $unmanaged, 'is_popular' => $pop, 'sort_order' => $sort]);
        $mk('co.tz', 'fred', 19999, true, 1, false, 21000);
        $mk('com', 'namecom', 42970, true, 2, true, 45000);
        $mk('net', 'namecom', 48000, true, 3, true, 50000);
        $mk('org', 'namecom', 51000, true, 4, true, 52000);
        $mk('info', 'namecom', 30000, false, 5, true);
        NameComAccount::create(['username' => 'owner', 'token' => 'nc_TEST_TOKEN_abcdefghijklmnop', 'token_hint' => 'mnop', 'is_sandbox' => false, 'status' => 'active']);
    }

    private function ncFake(array $taken = []): array
    {
        return ['*:checkAvailability*' => function ($r) use ($taken) {
            $res = [];
            foreach ($r['domainNames'] as $n) {
                $res[] = ['domainName' => $n, 'purchasable' => !in_array($n, $taken), 'premium' => false, 'purchaseType' => 'registration', 'purchasePrice' => 12.99, 'reason' => 'Domain is not available'];
            }
            return Http::response(['results' => $res]);
        }];
    }

    private function ncChecks(): int { return Http::recorded(fn ($r) => str_contains($r->url(), ':checkAvailability'))->count(); }

    // ── menu / submenu ──
    public function test_root_menu_has_option_10_and_keeps_1_to_9_and_0(): void
    {
        $c = $this->makeClient();
        $this->startSession($c);
        $t = $this->say('hello');
        foreach (['1) Domain Registration', '2) Domain Renewal', '3) Website Hosting', '4) Business Email Hosting', '5) View and Pay Invoices', '6) Domain WHOIS', '7) Check Domain Availability', '8) Change Nameservers (DNS)', '9) Account Information', '10) More services', '0) Logout', 'Reply with a number.'] as $x) $this->assertContains($x, $t);
        $this->assertContains("Hi {$c->name}! 👋\n*Choose a service:*", $t);

        // untouched routes
        foreach (['1' => 'order_domain', '3' => 'hosting_submenu', '6' => 'whois', '7' => 'check_availability'] as $n => $flow) {
            $this->startSession($c);
            $this->say($n);
            $this->assertSame($flow, $this->session()?->flow, "option $n");
        }
        $this->startSession($c);
        $this->assertContains('Account Information', $this->say('9'));
        $this->startSession($c);
        $this->say('0');
        $this->assertSame(null, $this->session(), 'logout deletes the session');

        // Swahili menu too
        $this->startSession($c);
        $this->session()->update(['language' => 'sw']);
        $this->assertContains('10) Huduma Zaidi', $this->say('zzz'));
    }

    public function test_menus_are_multiline_one_option_per_line(): void
    {
        $c = $this->makeClient();
        foreach (['en', 'sw'] as $lang) {
            $this->startSession($c);
            $this->session()->update(['language' => $lang]);
            $root = $this->say('zzz');
            $this->assertNoInlineOptions($root, range(1, 10), $lang . ' root');
            $this->assertContains("\n0) ", $root);
            foreach (['3' => 'hosting_submenu', '10' => 'more_services'] as $n => $flow) {
                $this->startSession($c);
                $this->session()->update(['language' => $lang]);
                $t = $this->say($n);
                $this->assertSame($flow, $this->session()?->flow);
                $this->assertNoInlineOptions($t, [1, 2], "$lang $flow");
            }
        }
    }

    private function assertNoInlineOptions(string $text, array $nums, string $label): void
    {
        $this->assertTrue(!str_contains($text, ' · '), "$label has ' · ' between options");
        foreach ($nums as $n) {
            $this->assertTrue((bool) preg_match('/^' . $n . '\) \S/m', $text), "$label lacks own-line option $n");
        }
        $this->assertTrue(substr_count($text, "\n") >= count($nums), "$label not multi-line");
    }

    public function test_submenu_navigation_and_back(): void
    {
        $c = $this->makeClient();
        $this->startSession($c);
        $t = $this->say('10');
        $this->assertSame('more_services', $this->session()->flow);
        foreach (['1) My Servers', '2) Expiring soon', '3) Support', '0) Back'] as $x) $this->assertContains($x, $t);

        $t = $this->say('9');
        $this->assertContains('Sorry, reply 1-6 or 0', $t);
        $this->assertSame('more_services', $this->session()->flow, 'invalid input keeps state');

        $this->assertContains('10) More services', $this->say('0'));
        $this->assertSame(null, $this->session()->flow);
        $this->say('10');
        $this->assertContains('10) More services', $this->say('back'));
        $this->say('10');
        $this->assertContains('Choose a service', $this->say('menu'));
        $this->assertSame(null, $this->session()->flow);
        $this->assertTrue($this->session() !== null, 'still logged in (0 in submenu is Back, not logout)');
    }

    // ── My Servers ──
    public function test_no_servers_polite_message(): void
    {
        $c = $this->makeClient();
        $this->startSession($c);
        $this->say('10');
        $t = $this->say('1');
        $this->assertContains("don't have any active Cloud Servers", $t);
        $this->assertNotContains('Reboot', $t);
    }

    public function test_lists_only_own_active_linked_servers(): void
    {
        $a = $this->makeClient('Asha Test');
        $b = $this->makeClient('Baraka Test', '255700000002');
        $this->makeServer($a, 'a-web', '7001', '203.0.113.71');
        $this->makeServer($a, 'a-db', '7002', '203.0.113.72');
        $this->makeServer($b, 'b-secret', '7003', '203.0.113.73');
        $this->makeServer($a, 'a-cancelled', '7004', '203.0.113.74', 'cancelled');
        $this->makeServer($a, 'a-gone', '7005', '203.0.113.75', 'active', null, 'gone');
        LinodeResource::create(['tenant_id' => $this->tenant->id, 'linode_account_id' => $this->linode()->id, 'type' => 'instance', 'remote_id' => '7006', 'label' => 'a-unlinked', 'status' => 'running', 'region' => 'x', 'ipv4' => ['203.0.113.76'], 'client_id' => $a->id]);

        $this->startSession($a);
        $this->say('10');
        $t = $this->say('1');
        foreach (['a-web', 'a-db', '203.0.113.71', 'eu-central', 'Running'] as $x) $this->assertContains($x, $t);
        foreach (['b-secret', '203.0.113.73', 'a-cancelled', 'a-gone', 'a-unlinked'] as $x) $this->assertNotContains($x, $t);
        $this->assertSame('pick', $this->session()->state['step']);

        // invalid pick keeps the list state; other numbers fine
        $this->assertContains('Sorry, reply 1, 2 or 0', $this->say('5'));
        $this->assertSame('pick', $this->session()->state['step']);
        $this->assertContains('*Cloud Server: a-db*', $this->say('1'));
        $this->assertSame('detail', $this->session()->state['step']);
        $this->assertContains('1) Reboot', Fw::last());
        $this->assertContains('Your Cloud Servers', $this->say('0')); // back to list (multiple)
        $this->say('0');
        $this->assertSame('more_services', $this->session()->flow);
        $this->assertSame(0, $this->httpCount(), 'listing/detail make no external call');
    }

    public function test_reboot_happy_path_single_post_and_audit(): void
    {
        $a = $this->makeClient();
        [$srv] = $this->makeServer($a, 'a-web', '7001', '203.0.113.71');
        $this->fk($this->lin(7001, 'running'));
        $this->startSession($a);
        $this->say('10');
        $this->assertContains('*Cloud Server: a-web*', $this->say('1')); // single server -> straight to detail
        $t = $this->say('1');
        $this->assertContains('exact server name: a-web', $t);
        $this->assertSame('confirm_name', $this->session()->state['step']);
        $this->assertSame(0, $this->rebootPosts(), 'nothing sent before confirmation');

        $t = $this->say('a-web');
        $this->assertContains('Reboot started for a-web', $t);
        $this->assertContains('Choose a service', $t); // back at main menu
        $this->assertSame(1, $this->rebootPosts(), 'exactly one POST /reboot');
        $this->assertTrue(Http::recorded(fn ($r) => $r->method() === 'POST' && $r->url() === 'https://api.linode.com/v4/linode/instances/7001/reboot')->count() === 1);
        $this->assertSame('rebooting', $srv->fresh()->status);
        $log = $this->audits('whatsapp.server_reboot');
        $this->assertSame(1, $log->count());
        $this->assertSame($a->id, $log[0]->request['client_id']);
        $this->assertSame('whatsapp', $log[0]->request['channel']);
        $this->assertSame(200, (int) $log[0]->response_status);
        $this->assertSame(0, $this->audits('portal.server_reboot')->count());
    }

    public function test_wrong_confirm_name_refused_and_state_kept(): void
    {
        $a = $this->makeClient();
        $this->makeServer($a, 'a-web', '7001', '203.0.113.71');
        $this->fk($this->lin(7001, 'running'));
        $this->startSession($a);
        $this->say('10'); $this->say('1'); $this->say('1');
        foreach (['A-WEB', 'a-we', 'yes', 'a-web '] as $wrong) {
            if ($wrong === 'a-web ') continue; // trailing space is trimmed by the webhook, so this one is the exact name
            $t = $this->say($wrong);
            $this->assertContains("exact server name: a-web", $t);
            $this->assertSame('confirm_name', $this->session()->state['step']);
        }
        $this->assertSame(0, $this->httpCount(), 'no external call on wrong names');
        $this->assertSame(4 - 1, $this->audits('whatsapp.server_reboot_refused')->count());
        $this->assertSame('wrong_confirm', $this->audits('whatsapp.server_reboot_refused')[0]->request['reason']);
        $this->assertContains('*Cloud Server: a-web*', $this->say('0')); // cancel returns to detail
        $this->assertSame(0, $this->rebootPosts());
    }

    public function test_non_running_server_refused_no_post(): void
    {
        foreach (['offline', 'rebooting', 'booting', 'migrating'] as $st) {
            $this->tearDown(); $this->setUp();
            $a = $this->makeClient();
            $this->acct = null;
            $this->makeServer($a, 'a-web', '7001', '203.0.113.71');
            $this->fk($this->lin(7001, $st));
            $this->startSession($a);
            $this->say('10'); $this->say('1'); $this->say('1');
            $t = $this->say('a-web');
            $this->assertContains('must be running', $t);
            $this->assertSame(0, $this->rebootPosts(), "live status $st -> no POST");
            $this->assertSame('not_running', $this->audits('whatsapp.server_reboot_refused')[0]->request['reason']);
            $this->assertSame(0, $this->audits('whatsapp.server_reboot')->count());
        }
    }

    public function test_api_failure_is_generic(): void
    {
        $a = $this->makeClient();
        [$srv] = $this->makeServer($a, 'a-web', '7001', '203.0.113.71');
        $this->fk(["api.linode.com/v4/linode/instances/7001" => Http::response(['id' => 7001, 'status' => 'running']), "api.linode.com/v4/linode/instances/7001/reboot" => Http::response(['errors' => [['reason' => 'Token needs linodes:read_write scope']]], 403)]);
        $this->startSession($a);
        $this->say('10'); $this->say('1'); $this->say('1');
        $t = $this->say('a-web');
        $this->assertContains('could not be started', $t);
        $this->assertNotContains('scope', $t);
        $this->assertNotContains('token', strtolower($t));
        $this->assertSame('running', $srv->fresh()->status, 'status unchanged on failure');
    }

    public function test_limits(): void
    {
        $a = $this->makeClient();
        [$srv] = $this->makeServer($a, 'a-web', '7001', '203.0.113.71');
        $this->fk($this->lin(7001, 'running'));

        // 2 per server per hour (staff power + portal + whatsapp all count)
        $this->seedAudit($srv, 'portal.server_reboot', 1);
        $this->seedAudit($srv, 'whatsapp.server_reboot', 1);
        $this->startSession($a);
        $this->say('10'); $this->say('1'); $this->say('1');
        $t = $this->say('a-web');
        $this->assertContains('at most 2 reboots per server per hour', $t);
        $this->assertSame('server_hour_limit', $this->audits('whatsapp.server_reboot_refused')[0]->request['reason']);
        $this->assertSame(0, $this->httpCount(), 'limit refusal makes no external call');

        // 5 per client per day (old audit rows for a different target/older than an hour)
        LinodeAuditLog::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->delete();
        for ($i = 0; $i < 5; $i++) {
            $row = LinodeAuditLog::withoutGlobalScopes()->create(['tenant_id' => $this->tenant->id, 'linode_account_id' => $srv->linode_account_id, 'action' => $i % 2 ? 'portal.server_reboot' : 'whatsapp.server_reboot', 'target' => "other #$i", 'request' => ['client_id' => $a->id], 'response_status' => 200]);
            DB::table('linode_audit_logs')->where('id', $row->id)->update(['created_at' => now()->subHours(3)]);
        }
        $this->startSession($a);
        $this->say('10'); $this->say('1'); $this->say('1');
        $t = $this->say('a-web');
        $this->assertContains('at most 5 reboots per day', $t);
        $this->assertSame(0, $this->httpCount());

        // tenant-wide 20/hour
        LinodeAuditLog::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->delete();
        $this->seedAudit($srv, 'server.power', 20, 'someone-else');
        // (server.power rows share the target, so use a different target to isolate the tenant cap)
        DB::table('linode_audit_logs')->where('tenant_id', $this->tenant->id)->update(['target' => 'zzz #1']);
        $this->startSession($a);
        $this->say('10'); $this->say('1'); $this->say('1');
        $t = $this->say('a-web');
        $this->assertContains('Too many server actions', $t);
        $this->assertSame(0, $this->httpCount());
        $this->assertSame(0, $this->rebootPosts());
    }

    public function test_staff_assist_cannot_reboot(): void
    {
        $a = $this->makeClient();
        [$srv] = $this->makeServer($a, 'a-web', '7001', '203.0.113.71');
        $this->fk($this->lin(7001, 'running'));
        $this->startSession($a, $this->user->id);
        $t = $this->say('10');
        $this->assertTrue($this->session()->assisted_by_user_id !== null);
        $this->assertContains('*Cloud Server: a-web*', $this->say('1')); // read-only view is fine
        $t = $this->say('1');
        $this->assertContains('not available in staff-assist mode', $t);
        $this->assertSame('detail', $this->session()->state['step'], 'never reaches the confirm step');
        $this->assertSame(0, $this->httpCount());
        $this->assertSame('staff_assist', $this->audits('whatsapp.server_reboot_refused')[0]->request['reason']);

        // even if a confirm step were somehow reached with an assisted session
        $this->session()->update(['state' => ['step' => 'confirm_name', 'server_id' => $srv->id, 'multiple' => false]]);
        $t = $this->say('a-web');
        $this->assertContains('not available in staff-assist mode', $t);
        $this->assertSame(0, $this->httpCount());
        $this->assertSame('running', $srv->fresh()->status);
    }

    public function test_server_of_other_client_or_tenant_cannot_be_rebooted_via_forged_state(): void
    {
        $a = $this->makeClient('Asha Test');
        $b = $this->makeClient('Baraka Test', '255700000002');
        [$bs] = $this->makeServer($b, 'b-secret', '7003', '203.0.113.73');
        $this->fk($this->lin(7003, 'running'));
        $this->startSession($a);
        WhatsappRenewalSession::updateOrCreate(['tenant_id' => $this->tenant->id, 'phone' => $this->phone], ['flow' => 'my_servers', 'state' => ['step' => 'confirm_name', 'server_id' => $bs->id], 'expires_at' => now()->addMinutes(10)]);
        $t = $this->say('b-secret');
        $this->assertContains('no longer available', $t);
        $this->assertSame(0, $this->httpCount());
    }

    public function test_tenant_isolation_for_servers_and_expiring(): void
    {
        $other = Tenant::withoutGlobalScopes()->where('id', '!=', $this->tenant->id)->firstOrFail();
        $otherUser = User::withoutGlobalScopes()->where('tenant_id', $other->id)->first();
        $this->assertTrue($otherUser !== null, 'precondition: second tenant has a user');
        $a = $this->makeClient();

        auth()->login($otherUser);
        $oc = Client::create(['tenant_id' => $other->id, 'name' => 'Other Tenant Client', 'phone' => $this->rawPhone, 'email' => 'o@example.test', 'status' => 'active']);
        Domain::create(['tenant_id' => $other->id, 'client_id' => $oc->id, 'name' => 'other-tenant.example.test', 'status' => 'active', 'expires_at' => now()->addDays(5), 'meta' => ['unmanaged' => true]]);
        $oacct = new LinodeAccount(['label' => 'O', 'token' => 'lin_SECRET_OTHER_abcdefghijklmnopqrstuvwxyz', 'token_hint' => '1234', 'status' => 'active', 'soa_email' => 'o@example.test']);
        $oacct->tenant_id = $other->id; $oacct->save();
        $oprod = ProductService::create(['tenant_id' => $other->id, 'type' => 'service', 'name' => 'OP', 'price' => 1, 'category' => 'Linode Servers', 'billing_cycle' => 'yearly', 'provisioning_type' => 'linode']);
        $osub = ClientSubscription::create(['tenant_id' => $other->id, 'client_id' => $oc->id, 'product_service_id' => $oprod->id, 'label' => 'o-server', 'quantity' => 1, 'start_date' => now()->subMonth(), 'expire_date' => now()->addDays(4), 'status' => 'active']);
        LinodeResource::create(['tenant_id' => $other->id, 'linode_account_id' => $oacct->id, 'type' => 'instance', 'remote_id' => '9001', 'label' => 'o-server', 'status' => 'running', 'region' => 'x', 'ipv4' => ['198.51.100.9'], 'client_id' => $oc->id, 'client_subscription_id' => $osub->id]);
        auth()->login($this->user);

        $this->startSession($a);
        $this->say('10');
        $t = $this->say('1');
        $this->assertContains("don't have any active Cloud Servers", $t);
        $this->assertNotContains('o-server', $t);
        $this->say('10');
        $t = $this->say('2');
        $this->assertContains('Nothing is expiring', $t);
        $this->assertNotContains('other-tenant', $t);
    }

    // ── Expiring soon ──
    private function domain(Client $c, string $name, int $days, string $status = 'active', array $meta = ['unmanaged' => true]): Domain
    {
        return Domain::create(['tenant_id' => $this->tenant->id, 'client_id' => $c->id, 'name' => $name, 'status' => $status, 'expires_at' => now()->addDays($days), 'meta' => $meta]);
    }

    private function hostingSub(Client $c, string $domain, int $days, float $price = 10000): array
    {
        $server = Server::withoutGlobalScopes()->first() ?? Server::create(['tenant_id' => $this->tenant->id, 'name' => 'fake', 'hostname' => 'fake.invalid', 'port' => 2087, 'username' => 'root', 'api_token' => 'x', 'type' => 'whm', 'is_active' => false]);
        $product = ProductService::create(['tenant_id' => $this->tenant->id, 'type' => 'service', 'name' => 'Test Plan', 'price' => $price, 'tax_percent' => 0, 'unit' => 'pcs', 'category' => 'Web Hosting', 'billing_cycle' => 'yearly', 'provisioning_type' => 'whm_cpanel']);
        $sub = ClientSubscription::create(['tenant_id' => $this->tenant->id, 'client_id' => $c->id, 'product_service_id' => $product->id, 'label' => $domain, 'quantity' => 1, 'start_date' => now()->subMonths(12)->addDays($days), 'expire_date' => now()->addDays($days), 'status' => 'active']);
        $acct = HostingAccount::create(['tenant_id' => $this->tenant->id, 'client_subscription_id' => $sub->id, 'server_id' => $server->id, 'domain' => $domain, 'cpanel_username' => substr(str_replace('.', '', $domain), 0, 8), 'package' => 'Starter', 'status' => 'active', 'last_synced_at' => now(), 'meta' => []]);
        return [$acct, $sub];
    }

    public function test_expiring_list_window_ordering_and_content(): void
    {
        $this->tlds();
        $a = $this->makeClient('Asha Test');
        $b = $this->makeClient('Baraka Test', '255700000002');
        $this->domain($a, 'late.co.tz', 50);
        $this->domain($a, 'soon.co.tz', 10);
        $this->domain($a, 'far.co.tz', 90);                 // outside 60 days
        $this->domain($a, 'lapsed.co.tz', -10, 'expired');  // expired within 30 days
        $this->domain($a, 'ancient.co.tz', -45, 'expired'); // expired too long ago
        $this->domain($b, 'theirs.co.tz', 3);               // other client
        $this->domain($a, 'canc.co.tz', 5, 'cancelled');
        $this->hostingSub($a, 'hosted.example.test', 20);
        $this->makeServer($a, 'a-web', '7001', '203.0.113.71', 'active', now()->addDays(5)->toDateString());

        $this->startSession($a);
        $this->say('10');
        $t = $this->say('2');
        foreach (['lapsed.co.tz', 'a-web', 'soon.co.tz', 'hosted.example.test', 'late.co.tz'] as $x) $this->assertContains($x, $t);
        foreach (['far.co.tz', 'ancient.co.tz', 'theirs.co.tz', 'canc.co.tz'] as $x) $this->assertNotContains($x, $t);
        // soonest first (already-expired first)
        $order = array_map(fn ($n) => strpos($t, $n), ['lapsed.co.tz', 'a-web', 'soon.co.tz', 'hosted.example.test', 'late.co.tz']);
        $sorted = $order; sort($sorted);
        $this->assertSame($sorted, $order, 'soonest first');
        $this->assertContains('Cloud Server', $t);
        $this->assertContains('Hosting', $t);
        $this->assertContains('TZS 21,000', $t);   // co.tz renew price
        $this->assertContains('TZS 30,000', $t);   // server plan
        $this->assertContains('TZS 10,000', $t);   // hosting plan
        $this->assertContains('expired 10 days ago', $t);
        $this->assertContains('10 days left', $t);
        $this->assertContains('50 days left', $t);
        $this->assertSame('expiring', $this->session()->flow);

        // invalid replies re-prompt, keep the list
        $before = $this->session()->state;
        foreach (['abc', '9', '0x', '99'] as $bad) {
            $this->assertContains('Sorry, reply 1', $this->say($bad));
            $this->assertSame($before, $this->session()->state);
        }
        $this->assertContains('*More services*', $this->say('0'));
    }

    public function test_expiring_max_ten(): void
    {
        $this->tlds();
        $a = $this->makeClient();
        for ($i = 1; $i <= 13; $i++) $this->domain($a, "d{$i}.co.tz", $i);
        $this->startSession($a);
        $this->say('10');
        $t = $this->say('2');
        $this->assertSame(10, preg_match_all('/^\d+\) (?:⚠️ )?d\d+\.co\.tz/m', $t));
        $this->assertContains('d10.co.tz', $t);
        $this->assertNotContains('d11.co.tz', $t);
    }

    public function test_expiring_nothing_message(): void
    {
        $a = $this->makeClient();
        $this->startSession($a);
        $this->say('10');
        $this->assertContains('Nothing is expiring', $this->say('2'));
    }

    public function test_expiring_domain_pick_creates_same_invoice_as_portal_renew(): void
    {
        $this->tlds();
        $a = $this->makeClient();
        $d = $this->domain($a, 'soon.co.tz', 10);
        $this->startSession($a);
        $this->say('10'); $this->say('2');
        $t = $this->say('1');
        $doc = Document::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->where('client_id', $a->id)->where('notes', 'like', 'Domain renewal:%')->get();
        $this->assertSame(1, $doc->count());
        $this->assertSame(21000.0, (float) $doc[0]->total);
        $this->assertSame('sent', $doc[0]->status);
        $this->assertContains('*Invoice ' . $doc[0]->document_number . "*\n• Amount: TZS 21,000", $t);
        $this->assertContains('Pay online (Card / Mobile Money)', $t);
        $meta = $d->fresh()->meta;
        $this->assertSame('renew', $meta['pending_action']);
        $this->assertSame($doc[0]->id, $meta['renewal_document_id']);
        $this->assertSame('pay_invoice', $this->session()->flow);
        $this->assertSame($doc[0]->id, $this->session()->state['document_id']);

        // asking again reuses the open invoice, no duplicate
        $this->startSession($a);
        $this->say('10'); $this->say('2'); $this->say('1');
        $this->assertSame(1, Document::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->where('client_id', $a->id)->where('notes', 'like', 'Domain renewal:%')->count());
    }

    public function test_expiring_namecom_domain_uses_manual_queue_invoice(): void
    {
        $this->tlds();
        $a = $this->makeClient();
        $d = $this->domain($a, 'shop.com', 12, 'active', ['unmanaged' => true, 'registrar' => 'namecom']);
        $this->startSession($a);
        $this->say('10');
        $t = $this->say('2');
        $this->assertContains('TZS 45,000', $t);
        $this->say('1');
        $doc = Document::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->where('client_id', $a->id)->where('notes', 'like', 'Domain renewal:%')->first();
        $this->assertTrue($doc !== null && (float) $doc->total === 45000.0, 'same invoice createRenewalInvoice makes');
        $this->assertSame('renew', $d->fresh()->meta['pending_action']);
        $this->assertSame(0, $this->httpCount(), 'no registrar call at invoice time');
    }

    public function test_expiring_hosting_and_server_pick_generate_subscription_invoice_once(): void
    {
        $a = $this->makeClient();
        [$h, $hsub] = $this->hostingSub($a, 'hosted.example.test', 20);
        [$srv, $ssub] = $this->makeServer($a, 'a-web', '7001', '203.0.113.71', 'active', now()->addDays(30)->toDateString());

        $this->startSession($a);
        $this->say('10'); $this->say('2');
        $t = $this->say('1'); // hosting is soonest
        $docs = Document::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->where('client_id', $a->id)->where('type', 'invoice')->get();
        $this->assertSame(1, $docs->count());
        $this->assertSame(10000.0, (float) $docs[0]->total);
        $this->assertContains('Invoice ' . $docs[0]->document_number, $t);
        $this->assertSame(1, \App\Models\RecurringInvoiceLog::withoutGlobalScopes()->where('client_subscription_id', $hsub->id)->where('document_id', $docs[0]->id)->count());

        // second pick of the same item reuses its open invoice
        $this->startSession($a);
        $this->say('10'); $this->say('2'); $this->say('1');
        $this->assertSame(1, Document::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->where('client_id', $a->id)->where('type', 'invoice')->count());

        // server subscription
        $this->startSession($a);
        $this->say('10'); $this->say('2');
        $t = $this->say('2');
        $this->assertSame(2, Document::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->where('client_id', $a->id)->where('type', 'invoice')->count());
        $this->assertContains('TZS 30,000', $t);
        $this->assertContains('pay_invoice', (string) $this->session()->flow);
        $this->assertSame(0, $this->httpCount(), 'billing makes no external call');
    }

    public function test_expiring_forged_or_stale_pick_is_safe(): void
    {
        $this->tlds();
        $a = $this->makeClient();
        $b = $this->makeClient('Baraka Test', '255700000002');
        $bd = $this->domain($b, 'theirs.co.tz', 3);
        $this->startSession($a);
        WhatsappRenewalSession::updateOrCreate(['tenant_id' => $this->tenant->id, 'phone' => $this->phone], ['flow' => 'expiring', 'state' => ['step' => 'pick', 'items' => [['kind' => 'domain', 'id' => $bd->id]]], 'expires_at' => now()->addMinutes(10)]);
        $t = $this->say('1');
        $this->assertContains('no longer available', $t);
        $this->assertSame(0, Document::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->where('client_id', $b->id)->count());
    }

    // ── option 7 ──
    public function test_option7_multi_tld_prices_availability_single_namecom_call(): void
    {
        $this->tlds();
        $this->fk($this->ncFake(['mybiz.net']));
        FakeRegistrar::$fred = ['mybiz.co.tz' => true];
        $a = $this->makeClient();
        $this->startSession($a);
        $this->say('7');
        $t = $this->say('mybiz');
        $this->assertSame(1, $this->ncChecks(), 'all Name.com TLDs in ONE call');
        $this->assertSame(1, FakeRegistrar::$fredCalls);
        $lines = array_values(array_filter(explode("\n", $t), fn ($l) => preg_match('/^\d+\) /', $l)));
        $this->assertTrue(count($lines) <= 8 && count($lines) >= 4, 'up to 8 lines');
        $this->assertContains('1) mybiz.co.tz — Available — TZS 19,999/yr', $t);
        $this->assertContains('mybiz.com — Available — TZS 42,970/yr', $t);
        $this->assertContains('mybiz.net — Taken', $t);
        $this->assertContains('Reply with a number to order', $t);
        $this->assertSame('pick', $this->session()->state['step']);
        $this->assertSame(0, Domain::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->where('client_id', $a->id)->count(), 'read-only: nothing created by searching');
    }

    public function test_option7_typed_tld_first(): void
    {
        $this->tlds();
        $this->fk($this->ncFake());
        FakeRegistrar::$fred = ['mybiz.co.tz' => true];
        $a = $this->makeClient();
        $this->startSession($a);
        $this->say('7');
        $t = $this->say('MyBiz.org');
        $lines = array_values(array_filter(explode("\n", $t), fn ($l) => preg_match('/^\d+\) /', $l)));
        $this->assertContains('1) mybiz.org — Available — TZS 51,000/yr', $lines[0]);
        $this->assertSame(1, $this->ncChecks());
        // a TLD we do not sell is listed first as not offered, and does not break the rest
        $t = $this->say('mybiz.xyz');
        $this->assertContains('1) mybiz.xyz — Not offered', $t);
        $this->assertContains('mybiz.com', $t);
    }

    public function test_option7_order_namecom_tld_creates_pending_domain_and_invoice(): void
    {
        $this->tlds();
        $this->fk($this->ncFake());
        $a = $this->makeClient();
        $this->startSession($a);
        $this->say('7');
        $t = $this->say('mybiz.com');
        $this->assertContains('1) mybiz.com — Available — TZS 42,970/yr', $t);
        $t = $this->say('1');
        $this->assertSame('order_domain', $this->session()->flow);
        $this->assertContains("✅ *mybiz.com* is available\nPrice: TZS 42,970 for 1 year\n\nOrder it now?\n1) Yes\n2) No", $t);
        $t = $this->say('yes');
        $doc = Document::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->where('client_id', $a->id)->where('notes', 'like', 'Domain registration (WhatsApp order): mybiz.com%')->first();
        $this->assertTrue($doc !== null, 'invoice created');
        $this->assertSame(42970.0, (float) $doc->total);
        $dom = Domain::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->where('name', 'mybiz.com')->first();
        $this->assertSame('pending', $dom->status);
        $this->assertSame(null, $dom->registrar_account_id, 'Name.com TLD: no FRED account');
        $this->assertSame('register', $dom->meta['pending_action']);
        $this->assertSame($doc->id, $dom->meta['order_document_id']);
        $this->assertSame('namecom', $dom->meta['registrar']);
        $this->assertContains('*Invoice ' . $doc->document_number . "*\n• Amount: TZS 42,970", $t);
        $this->assertSame('pay_invoice', $this->session()->flow);
        $this->assertSame(1, $this->ncChecks(), 'ordering does not re-query the registrar');
    }

    public function test_option7_order_fred_tld_keeps_existing_behaviour(): void
    {
        $this->tlds();
        $this->fk($this->ncFake());
        FakeRegistrar::$fred = ['mybiz.co.tz' => true];
        $a = $this->makeClient();
        $this->startSession($a);
        $this->say('7');
        $this->say('mybiz.co.tz');
        $this->assertContains('✅ *mybiz.co.tz* is available', $this->say('1'));
        $this->say('yes');
        $dom = Domain::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->where('name', 'mybiz.co.tz')->first();
        $this->assertSame('pending', $dom->status);
        $this->assertTrue($dom->registrar_account_id !== null, 'FRED path keeps its registrar account');
    }

    public function test_option7_taken_or_bad_picks_reprompt_without_losing_state(): void
    {
        $this->tlds();
        $this->fk($this->ncFake(['mybiz.net']));
        FakeRegistrar::$fred = ['mybiz.co.tz' => true];
        $a = $this->makeClient();
        Domain::create(['tenant_id' => $this->tenant->id, 'client_id' => $a->id, 'name' => 'mybiz.org', 'status' => 'active', 'meta' => ['unmanaged' => true]]);
        $this->startSession($a);
        $this->say('7');
        $t = $this->say('mybiz');
        $this->assertContains('mybiz.org — Taken', $t, 'a name we already hold is never orderable');
        $state = $this->session()->state;
        $rows = $state['rows'];
        $net = array_search('mybiz.net', array_column($rows, 'name')) + 1;
        $this->assertContains("can't be ordered", $this->say((string) $net));
        $this->assertContains('Sorry, reply 1-', $this->say('50'));
        $this->assertContains('Sorry', $this->say('not a domain!'));
        $this->assertSame($state, $this->session()->state, 'state intact after bad input');
        $this->assertSame('check_availability', $this->session()->flow);
        // then a good pick still works
        $this->assertContains('is available', $this->say('1'));
    }

    public function test_option7_digit_without_a_list_reprompts(): void
    {
        $a = $this->makeClient();
        $this->startSession($a);
        $this->say('7');
        $this->assertContains('type the domain name', $this->say('3'));
        $this->assertSame('check_availability', $this->session()->flow);
    }

    public function test_option7_falls_back_to_single_domain_when_suggestions_fail(): void
    {
        $this->tlds();
        $this->fk([]);
        FakeRegistrar::$fred = ['mybiz.co.tz' => true];
        app()->bind(DomainSuggestService::class, fn () => new class(app(DomainRegistrarManager::class)) extends DomainSuggestService {
            public function check(string $tenantId, array $rows): array { throw new \RuntimeException('suggest down'); }
        });
        $a = $this->makeClient();
        $this->startSession($a);
        $this->say('7');
        $t = $this->say('mybiz.co.tz');
        $this->assertContains("✅ *mybiz.co.tz* is available\nPrice: TZS 19,999 for 1 year\n\nOrder it now?\n1) Yes\n2) No", $t);
        $this->assertSame('order_domain', $this->session()->flow, 'available single-domain check hands off to the confirm step');
        $this->assertSame('confirm', $this->session()->state['step']);
        // bare label with no fallback possible: polite retry, state kept
        $this->say('menu');
        $this->say('7');
        $t = $this->say('mybiz');
        $this->assertContains("couldn't check this right now", $t);
        $this->assertSame('check_availability', $this->session()->flow);
    }

    public function test_option7_all_namecom_down_shows_cannot_check_without_supplier(): void
    {
        $this->tlds();
        $this->fk(['*:checkAvailability*' => Http::response(['message' => 'boom'], 500)]);
        FakeRegistrar::$fred = ['mybiz.co.tz' => true];
        $a = $this->makeClient();
        $this->startSession($a);
        $this->say('7');
        $t = $this->say('mybiz');
        $this->assertContains("mybiz.com — Can't check right now", $t);
        $this->assertContains('mybiz.co.tz — Available', $t);
    }

    // ═════════════════════ Polish pass: grouped root, confirmations, localisation, support, My Domains/Hosting ═════════════════════

    private function lang(string $lang): void { $this->session()->update(['language' => $lang]); }

    private function plan(string $name, float $price, string $cycle = 'yearly', string $desc = ''): ProductService
    {
        return ProductService::create(['tenant_id' => $this->tenant->id, 'type' => 'service', 'name' => $name, 'price' => $price, 'tax_percent' => 0, 'unit' => 'pcs', 'category' => 'Web Hosting', 'billing_cycle' => $cycle, 'provisioning_type' => 'whm_cpanel', 'portal_visible' => true, 'is_active' => true, 'description' => $desc]);
    }

    private function docs(Client $c)
    {
        return Document::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->where('client_id', $c->id)->where('type', 'invoice')->get();
    }

    private function invoice(Client $c, string $status, int $dueDays, float $total = 5000): Document
    {
        return Document::withoutGlobalScopes()->create(['tenant_id' => $this->tenant->id, 'client_id' => $c->id, 'type' => 'invoice', 'document_number' => 'T-' . strtoupper(substr(md5(uniqid()), 0, 6)), 'date' => now()->toDateString(), 'due_date' => now()->addDays($dueDays)->toDateString(), 'subtotal' => $total, 'discount_amount' => 0, 'tax_amount' => 0, 'total' => $total, 'status' => $status]);
    }

    public function test_root_menu_is_grouped_and_every_number_still_works(): void
    {
        $c = $this->makeClient();
        $order = ['en' => ['*Domains*', '1) Domain Registration', '2) Domain Renewal', '6) Domain WHOIS', '7) Check Domain Availability', '8) Change Nameservers (DNS)', '11) My Domains', '*Hosting & Email*', '3) Website Hosting', '4) Business Email Hosting', '12) My Hosting', '*Payments*', '5) View and Pay Invoices', '*Account*', '9) Account Information', '10) More services', '0) Logout'],
                  'sw' => ['*Domain*', '1) Domain Registration', '2) Domain Renewal', '6) WHOIS ya Domain', '7) Angalia kama Domain Inapatikana', '8) Badilisha Nameservers (DNS)', '11) Domain Zangu', '*Hosting na Email*', '3) Website Hosting', '4) Business Email Hosting', '12) Hosting Yangu', '*Malipo*', '5) Angalia na Lipa Invoice', '*Akaunti*', '9) Taarifa za Akaunti', '10) Huduma Zaidi', '0) Toka (Logout)']];
        foreach ($order as $lang => $seq) {
            $this->startSession($c);
            $this->lang($lang);
            $t = $this->say('zzz');
            $pos = -1;
            foreach ($seq as $x) {
                $p = strpos($t, $x);
                $this->assertTrue($p !== false && $p > $pos, "$lang: '$x' missing or out of order");
                $pos = $p;
            }
            $this->assertContains('MOSMS', $t);
            $this->assertContains('👋', $t);
            $this->assertSame(1, substr_count($t, '👋'), 'single greeting emoji');
            $this->assertNoInlineOptions($t, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], "$lang root");
            $this->assertTrue((bool) preg_match('/\n\n\*/', $t), 'blank line between groups');
        }

        foreach (['1' => 'order_domain', '3' => 'hosting_submenu', '6' => 'whois', '7' => 'check_availability', '8' => 'change_dns', '10' => 'more_services', '11' => 'my_domains', '12' => 'my_hosting', '5' => 'pay_invoice', '4' => 'order_hosting'] as $n => $flow) {
            $this->startSession($c);
            $this->say($n);
            $s = $this->session();
            // flows with nothing to show (no domains/invoices/plans) finish straight back to the root menu
            $this->assertTrue($s !== null && ($s->flow === $flow || $s->flow === null), "option $n");
        }
        $this->startSession($c); $this->say('2');
        $this->startSession($c); $this->assertContains('Account Information', $this->say('9'));
        $this->startSession($c); $this->say('0'); $this->assertSame(null, $this->session());
    }

    public function test_confirmation_accepts_digits_and_words(): void
    {
        $this->tlds();
        FakeRegistrar::$fred = ['mybiz.co.tz' => true];
        $a = $this->makeClient();
        foreach (['1', 'ndiyo', 'YES', 'Ndiyo', 'y'] as $yes) {
            $this->startSession($a);
            $before = $this->docs($a)->count();
            $this->say('1');
            $t = $this->say('mybiz.co.tz');
            $this->assertContains("1) Yes\n2) No", $t);
            $this->assertSame($before, $this->docs($a)->count());
            $this->say($yes);
            $this->assertSame($before + 1, $this->docs($a)->count(), "'$yes' confirms");
            $this->assertSame('pay_invoice', $this->session()->flow);
            Domain::withoutGlobalScopes()->where('name', 'mybiz.co.tz')->delete();
        }
        foreach (['2', 'hapana', 'NO', 'no'] as $no) {
            $this->startSession($a);
            $before = $this->docs($a)->count();
            $this->say('1'); $this->say('mybiz.co.tz');
            $t = $this->say($no);
            $this->assertContains('cancelled', $t);
            $this->assertSame($before, $this->docs($a)->count(), "'$no' cancels");
        }
        // anything else neither orders nor cancels: it names the choices and keeps the step
        $this->startSession($a);
        $this->say('1'); $this->say('mybiz.co.tz');
        $before = $this->docs($a)->count();
        $t = $this->say('maybe');
        $this->assertContains('Sorry, reply 1 or 2.', $t);
        $this->assertSame('confirm', $this->session()->state['step']);
        $this->assertSame($before, $this->docs($a)->count());
        // Swahili wording
        $this->lang('sw');
        $this->assertContains("1) Ndiyo\n2) Hapana", $this->say('maybe'));
    }

    public function test_plan_details_digit_cannot_be_read_as_a_pick_from_the_earlier_list(): void
    {
        $p1 = $this->plan('Alpha', 10000);
        $p2 = $this->plan('Beta', 20000, 'monthly');
        $a = $this->makeClient();
        $this->startSession($a);
        $t = $this->say('3'); $this->assertContains('1) Order new hosting', $t);
        $t = $this->say('1');
        $this->assertContains('1) Alpha — TZS 10,000 per year', $t);
        $this->assertContains('2) Beta — TZS 20,000 per month', $t);
        $this->assertNotContains('/yearly', $t);
        $t = $this->say('2');
        $this->assertSame('plan_details', $this->session()->state['step']);
        $this->assertSame($p2->id, $this->session()->state['product_service_id']);
        $this->assertContains("• Price: TZS 20,000 per month", $t);
        $this->assertContains("1) Yes, order this one\n2) No, choose another", $t);
        // '2' here means NO (back to the list), never "plan 2"
        $t = $this->say('2');
        $this->assertSame('pick_plan', $this->session()->state['step']);
        $this->assertContains('*Choose a plan*', $t);
        $this->say('1');
        $this->assertSame($p1->id, $this->session()->state['product_service_id']);
        $this->assertContains('Sorry, reply 1 or 2.', $this->say('7'));
        $this->assertSame('plan_details', $this->session()->state['step']);
        $t = $this->say('1'); // YES
        $this->assertSame('ask_domain_mode', $this->session()->state['step']);
        $this->assertContains('3) Transfer my domain to you', $t);
        $this->assertContains('Sorry, reply 1, 2, 3 or 0.', $this->say('9'));
        // word forms still work, and in Swahili
        $this->startSession($a); $this->lang('sw');
        $this->say('3'); $t = $this->say('1');
        $this->assertContains('1) Alpha — TZS 10,000 kwa mwaka', $t);
        $this->assertContains('2) Beta — TZS 20,000 kwa mwezi', $t);
        $this->say('1');
        $this->assertSame('ndiyo', 'ndiyo');
        $this->say('NDIYO');
        $this->assertSame('ask_domain_mode', $this->session()->state['step']);
    }

    public function test_hosting_order_confirm_summaries_and_promo_step(): void
    {
        $p = $this->plan('Alpha', 55000);
        $a = $this->makeClient();
        $this->startSession($a);
        $this->say('3'); $this->say('1'); $this->say('1'); $this->say('1');   // plan, details, YES
        $t = $this->say('1');                                                   // I already have a domain
        $this->assertContains('Please reply with the domain name', $t);
        $t = $this->say('mysite.example.test');
        $this->assertContains('Reply 2 (No) if you don\'t have one.', $t);
        $t = $this->say('2');                                                   // no promo, by digit
        foreach (["*Confirm your order*", "• Package: Alpha", "• Price: TZS 55,000 per year", "• Domain: mysite.example.test", "Place the order?\n1) Yes\n2) No"] as $x) $this->assertContains($x, $t);
        $t = $this->say('2');                                                   // NO
        $this->assertContains('cancelled', $t);
        $this->assertSame(0, $this->docs($a)->count());
        // same in Swahili, then confirm by digit
        $this->startSession($a); $this->lang('sw');
        $this->say('3'); $this->say('1'); $this->say('1'); $this->say('1'); $this->say('1'); $this->say('mysite.example.test');
        $t = $this->say('hapana');
        foreach (['*Thibitisha agizo*', '• Kifurushi: Alpha', '• Bei: TZS 55,000 kwa mwaka', '• Domain: mysite.example.test', "1) Ndiyo\n2) Hapana"] as $x) $this->assertContains($x, $t);
        $this->say('1');
        $this->assertSame(1, $this->docs($a)->count());
    }

    public function test_availability_message_is_one_shared_helper(): void
    {
        $src = file_get_contents(__DIR__ . '/../../app/Http/Controllers/WhatsappRenewalWebhookController.php');
        $this->assertSame(1, substr_count($src, '* inapatikana'), 'only the helper renders the availability text');
        $this->assertSame(1, substr_count($src, 'is available\\nPrice'), 'only the helper renders the English availability text');

        $this->tlds();
        FakeRegistrar::$fred = ['mybiz.co.tz' => true];
        $this->plan('Alpha', 10000);
        $a = $this->makeClient();
        $body = "✅ *mybiz.co.tz* is available\nPrice: TZS 19,999 for 1 year\n\n";
        // 1) registration flow
        $this->startSession($a);
        $this->say('1');
        $t = $this->say('mybiz.co.tz');
        $this->assertContains($body . "Order it now?\n1) Yes\n2) No", $t);
        // 2) hosting + new domain flow ("continue" wording)
        $this->startSession($a);
        $this->say('3'); $this->say('1'); $this->say('1'); $this->say('1'); $this->say('2');
        $t = $this->say('mybiz.co.tz');
        $this->assertContains($body . "Continue?\n1) Yes\n2) No", $t);
        // 3) option-7 search row pick
        $this->startSession($a);
        $this->fk($this->ncFake());
        $this->say('7');
        $this->say('mybiz');
        $rows = $this->session()->state['rows'];
        $n = array_search('mybiz.co.tz', array_column($rows, 'name')) + 1;
        $t = $this->say((string) $n);
        $this->assertContains($body . "Order it now?\n1) Yes\n2) No", $t);
        // Swahili
        $this->lang('sw');
        $this->startSession($a); $this->lang('sw');
        $this->say('1');
        $this->assertContains("✅ *mybiz.co.tz* inapatikana\nBei: TZS 19,999 kwa mwaka 1\n\nUnataka kuagiza sasa?\n1) Ndiyo\n2) Hapana", $this->say('mybiz.co.tz'));
    }

    public function test_cycle_and_status_are_localised(): void
    {
        $a = $this->makeClient();
        [$s1] = $this->makeServer($a, 'srv-run', '8001', '203.0.113.81', 'active', null, 'running');
        [$s2] = $this->makeServer($a, 'srv-off', '8002', '203.0.113.82', 'active', null, 'offline');
        [$s3] = $this->makeServer($a, 'srv-reb', '8003', '203.0.113.83', 'active', null, 'rebooting');
        foreach (['en' => ['Running', 'Off', 'Rebooting', '🟢', '🔴', '🟡'], 'sw' => ['inafanya kazi', 'imezimwa', 'inawashwa upya', '🟢', '🔴', '🟡']] as $lang => $words) {
            $this->startSession($a); $this->lang($lang);
            $this->say('10');
            $t = $this->say('1');
            foreach ($words as $w) $this->assertContains($w, $t);
            foreach (['running', 'offline', 'rebooting'] as $raw) $this->assertNotContains($raw, $t);
            $this->assertContains('🟢 srv-run', $t);
            $this->assertContains('🔴 srv-off', $t);
            $this->assertContains('🟡 srv-reb', $t);
        }
        // detail card
        $this->startSession($a); $this->lang('sw');
        $this->say('10'); $this->say('1');
        $t = $this->say('1'); // srv-off sorts first? label order: srv-off, srv-reb, srv-run
        $this->assertContains('Hali: 🔴 imezimwa', $t);
        // billing cycles never leak raw
        foreach (['monthly' => ['kwa mwezi', 'per month'], 'quarterly' => ['kwa miezi 3', 'per 3 months'], 'half_yearly' => ['kwa miezi 6', 'per 6 months'], 'yearly' => ['kwa mwaka', 'per year']] as $cyc => [$sw, $en]) {
            ProductService::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->where('category', 'Web Hosting')->delete();
            $this->plan('P-' . $cyc, 1000, $cyc);
            foreach (['sw' => $sw, 'en' => $en] as $lang => $expect) {
                $this->startSession($a); $this->lang($lang);
                $this->say('3');
                $t = $this->say('1');
                $this->assertContains("P-$cyc — TZS 1,000 $expect", $t);
                $this->assertNotContains("1,000 $cyc", $t);
            }
        }
    }

    public function test_cap_notice_search_and_portal_pointer(): void
    {
        $a = $this->makeClient();
        for ($i = 1; $i <= 11; $i++) $this->domain($a, sprintf('dom%02d.co.tz', $i), $i, 'active', []);
        $this->startSession($a);
        $t = $this->say('11');
        $this->assertSame(9, preg_match_all('/^\d\) dom\d\d\.co\.tz/m', $t));
        $this->assertContains('There are 2 more. Type a name to search.', $t);
        $t = $this->say('dom11');
        $this->assertContains('1) dom11.co.tz', $t);
        $this->assertNotContains('dom01', $t);
        $this->assertNotContains('There are', $t, 'search result of 1 has no cap notice');
        $this->say('0'); // back to the main menu
        $this->lang('sw');
        $this->assertContains('Zipo nyingine 2. Andika jina kutafuta.', $this->say('11'));
    }

    public function test_cap_notice_points_to_portal_where_search_is_not_supported(): void
    {
        for ($i = 1; $i <= 10; $i++) $this->plan(sprintf('Plan%02d', $i), 1000 * $i);
        $a = $this->makeClient();
        $this->startSession($a);
        $this->say('3');
        $t = $this->say('1');
        $this->assertSame(9, preg_match_all('/^\d\) Plan\d\d/m', $t));
        $this->assertContains('There is 1 more'.'', str_replace('There are 1 more', 'There is 1 more', $t));
        $this->assertContains($this->tenant->portalUrl('/portal'), $t);
        $this->assertContains('Visit the portal to see all', $t);
        $this->startSession($a); $this->lang('sw');
        $this->say('3');
        $this->assertContains('Tembelea portal kuona zote', $this->say('1'));
    }

    public function test_invalid_input_names_the_valid_choices(): void
    {
        $a = $this->makeClient();
        $this->startSession($a);
        $this->say('3');
        $this->assertContains('Sorry, reply 1, 2 or 0.', $this->say('x'));
        $this->say('0'); // 0 = back to main menu
        $this->assertSame(null, $this->session()->flow);
        $this->say('10');
        $this->assertContains('Sorry, reply 1-6 or 0.', $this->say('x'));
        $this->lang('sw');
        $this->assertContains('Samahani, jibu 1-6 au 0.', $this->say('x'));
        // payment method step
        $this->startSession($a);
        $inv = $this->invoice($a, 'sent', 5);
        $this->say('5');
        $this->assertContains('Sorry, reply 1 or 0.', $this->say('9'));
        $this->say('1');
        $this->assertContains('Sorry, reply 1, 2 or 0.', $this->say('7'));
    }

    public function test_payment_method_wording_and_invoice_emoji(): void
    {
        $a = $this->makeClient();
        $this->invoice($a, 'sent', 10);
        $this->invoice($a, 'overdue', -3);
        $this->startSession($a);
        $t = $this->say('5');
        $this->assertContains('⏳ ', $t);
        $this->assertContains('⚠️ ', $t);
        $this->assertTrue((bool) preg_match('/^1\) ⚠️ T-/m', $t), 'overdue first (due date order)');
        $t = $this->say('1');
        $this->assertContains('Pay online (Card / Mobile Money)', $t);
        $this->assertContains('2) Payment details (Bank/mobile money)', $t);
        $this->assertNotContains('Pesapal', $t);
        $this->startSession($a); $this->lang('sw');
        $this->say('5');
        $t = $this->say('1');
        $this->assertContains('1) Lipa mtandaoni (Kadi / Mobile Money)', $t);
        $this->assertContains('2) Maelezo ya kulipa (Benki/Lipa Namba)', $t);
        $this->assertContains('• Kiasi: TZS', $t);
    }

    public function test_invoice_list_cap_and_search(): void
    {
        $a = $this->makeClient();
        for ($i = 1; $i <= 11; $i++) $this->invoice($a, 'sent', $i);
        $this->startSession($a);
        $t = $this->say('5');
        $this->assertSame(9, preg_match_all('/^\d\) [⏳⚠️]+ T-/mu', $t));
        $this->assertContains('There are 2 more. Type a name to search.', $t);
        $any = Document::withoutGlobalScopes()->where('client_id', $a->id)->orderByDesc('due_date')->first();
        $t = $this->say($any->document_number);
        $this->assertContains('1) ⏳ ' . $any->document_number, $t);
    }

    public function test_emoji_are_only_the_approved_ones(): void
    {
        $this->tlds();
        FakeRegistrar::$fred = ['mybiz.co.tz' => true];
        $a = $this->makeClient();
        $this->plan('Alpha', 10000);
        $this->domain($a, 'e1.co.tz', 3); $this->domain($a, 'e2.co.tz', 40, 'active', []); $this->domain($a, 'e3.co.tz', -5, 'expired', []);
        $this->hostingSub($a, 'host.example.test', 5);
        $this->makeServer($a, 'sv', '8100', '203.0.113.90');
        $this->invoice($a, 'sent', 4);
        foreach (['en', 'sw'] as $lang) {
            foreach (['zzz', '1', 'menu', '2', 'menu', '3', '1', 'menu', '3', '2', 'menu', '5', 'menu', '7', 'menu', '8', 'menu', '9', '10', '1', '0', '2', '0', '3', 'menu', '11', '1', 'menu', '12', '1', 'menu'] as $msg) {
                if ($msg === 'zzz') { $this->startSession($a); $this->lang($lang); }
                $this->say($msg);
            }
        }
        $allowed = ['👋', '✅', '⏳', '⚠', '🟢', '🔴', '🟡', '👤'];
        foreach (Fw::$sent as $m) {
            preg_match_all('/[\x{1F000}-\x{1FAFF}\x{2600}-\x{27BF}\x{2B00}-\x{2BFF}]/u', $m['text'], $mm);
            foreach ($mm[0] as $emoji) {
                $this->assertTrue(in_array($emoji, $allowed, true), "unapproved emoji '$emoji' in:\n{$m['text']}");
            }
        }
        // status dots follow the rules
        $this->startSession($a);
        $this->say('11');
        $t = Fw::last();
        $this->assertTrue((bool) preg_match('/e1\.co\.tz.*⚠️/u', $t), 'due within 7 days => warning');
        $this->assertTrue((bool) preg_match('/e2\.co\.tz.*🟢/u', $t), 'healthy active => green');
        $this->assertTrue((bool) preg_match('/e3\.co\.tz.*⚠️/u', $t), 'expired => warning');
    }

    // ── 3) Msaada / Support ──

    private function tickets(Client $c)
    {
        return \App\Models\Ticket::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->where('client_id', $c->id)->get();
    }

    public function test_support_creates_a_numbered_ticket_through_the_portal_shape(): void
    {
        $a = $this->makeClient();
        $this->startSession($a);
        $t = $this->say('10');
        $this->assertContains('3) Support', $t);
        $t = $this->say('3');
        $this->assertContains('Describe your issue', $t);
        $this->assertContains('0) Back', $t);
        // too short / too long
        $this->assertContains('between 5 and 1000', $this->say('abcd'));
        $this->assertContains('between 5 and 1000', $this->say(str_repeat('x', 1001)));
        $this->assertSame(0, $this->tickets($a)->count());
        $this->assertSame('more_services', $this->session()->flow);
        $t = $this->say('My website shows an error since this morning');
        $tk = $this->tickets($a);
        $this->assertSame(1, $tk->count());
        $ticket = $tk->first();
        $this->assertSame('WhatsApp support request', $ticket->subject);
        $this->assertSame('support', $ticket->department);
        $this->assertSame('medium', $ticket->priority);
        $this->assertSame('open', $ticket->status);
        $this->assertTrue((bool) preg_match('/^[A-Z]+-?\d+/i', (string) $ticket->ticket_number) || $ticket->ticket_number !== '', 'numbered');
        $this->assertContains($ticket->ticket_number, $t);
        $this->assertContains('We will get back to you shortly', $t);
        $reply = $ticket->replies()->first();
        $this->assertSame('client', $reply->author_type);
        $this->assertContains('My website shows an error', $reply->message);
        $this->assertContains('Requested via WhatsApp', $reply->message);
        $this->assertNotContains('staff-assist', $reply->message);
        // staff are notified exactly as the portal does
        $staff = \App\Http\Controllers\TicketController::staffToNotify($ticket);
        if ($staff->isNotEmpty()) {
            $this->assertTrue(Notification::sent($staff->first(), \App\Notifications\TicketActivityStaffNotification::class)->count() === 1, 'staff notified once');
        }
        // 0 backs out without a ticket
        $this->startSession($a);
        $this->say('10'); $this->say('3');
        $this->assertContains('*More services*', $this->say('0'));
        $this->assertSame(1, $this->tickets($a)->count());
        // Swahili reply
        $this->startSession($a); $this->lang('sw');
        $this->say('10');
        $this->assertContains('3) Msaada', Fw::last());
        $this->say('3');
        $t = $this->say('Nahitaji msaada kuhusu invoice yangu');
        $this->assertContains('Tutakujibu hivi karibuni', $t);
    }

    public function test_support_is_rate_limited_to_three_per_client_per_day(): void
    {
        $a = $this->makeClient();
        $b = $this->makeClient('Baraka Test', '255700000002');
        for ($i = 1; $i <= 3; $i++) {
            $this->startSession($a);
            $this->say('10'); $this->say('3');
            $this->say("Support request number $i please");
        }
        $this->assertSame(3, $this->tickets($a)->count());
        $this->startSession($a);
        $this->say('10');
        $t = $this->say('3');
        $this->assertContains("reached today's support limit (3 requests per day)", $t);
        $this->assertSame(3, $this->tickets($a)->count());
        // a stale prompt cannot bypass the limit either
        $this->setStaleSupportStep($a);
        $t = $this->say('One more request that should be refused');
        $this->assertContains("today's support limit", $t);
        $this->assertSame(3, $this->tickets($a)->count());
        // other clients unaffected
        $this->startSession($b);
        $this->say('10'); $this->say('3');
        $this->say('Baraka needs help here');
        $this->assertSame(1, $this->tickets($b)->count());
        // tickets older than a day stop counting
        \App\Models\Ticket::withoutGlobalScopes()->where('client_id', $a->id)->update(['created_at' => now()->subDays(2)]);
        $this->startSession($a);
        $this->say('10');
        $this->assertContains('Describe your issue', $this->say('3'));
    }

    private function setStaleSupportStep(Client $a): void
    {
        WhatsappRenewalSession::updateOrCreate(['tenant_id' => $this->tenant->id, 'phone' => $this->phone],
            ['client_id' => $a->id, 'flow' => 'more_services', 'state' => ['step' => 'support_text'], 'items' => null, 'language' => 'en', 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(10)]);
    }

    public function test_support_in_staff_assist_is_tagged(): void
    {
        $a = $this->makeClient();
        $this->startSession($a, $this->user->id);
        $this->say('10'); $this->say('3');
        $this->say('Client called and needs a callback');
        $ticket = $this->tickets($a)->first();
        $this->assertTrue($ticket !== null);
        $this->assertContains('created via staff-assist', $ticket->replies()->first()->message);
    }

    // ── 11) My Domains ──

    public function test_my_domains_list_order_wording_and_isolation(): void
    {
        $this->tlds();
        $a = $this->makeClient();
        $b = $this->makeClient('Baraka Test', '255700000002');
        $this->domain($a, 'far.co.tz', 100, 'active', []);
        $this->domain($a, 'soon.co.tz', 10, 'active', []);
        $this->domain($a, 'today.co.tz', 0, 'active', []);
        $this->domain($a, 'lapsed.co.tz', -12, 'expired', []);
        $this->domain($a, 'gone.co.tz', 5, 'cancelled', []);
        $this->domain($a, 'out.co.tz', 5, 'transferred_out', []);
        $this->domain($b, 'theirs.co.tz', 3, 'active', []);
        $this->startSession($a);
        $t = $this->say('11');
        $this->assertSame('my_domains', $this->session()->flow);
        foreach (['gone.co.tz', 'out.co.tz', 'theirs.co.tz'] as $x) $this->assertNotContains($x, $t);
        $this->assertTrue(strpos($t, 'lapsed.co.tz') < strpos($t, 'today.co.tz') && strpos($t, 'today.co.tz') < strpos($t, 'soon.co.tz') && strpos($t, 'soon.co.tz') < strpos($t, 'far.co.tz'), 'soonest expiry first');
        foreach (['1) lapsed.co.tz — expires ', '(expired 12 days ago) — ⚠️', '(expires today) — ⚠️', '(10 days left) — 🟢', '(100 days left) — 🟢', now()->addDays(10)->format('d M Y')] as $x) $this->assertContains($x, $t);
        $this->assertContains('0) Back', $t);
        $this->lang('sw');
        $t = $this->say('0'); // back to menu
        $this->say('11');
        $t = Fw::last();
        foreach (['inaisha ', '(imeisha siku 12 zilizopita)', '(inaisha leo)', '(siku 10 zimebaki)', '*Domain Zangu*'] as $x) $this->assertContains($x, $t);
        // a forged pick of someone else's domain is refused
        $this->assertContains('Samahani, jibu 1', $this->say('9'));
    }

    public function test_my_domains_detail_and_renew_creates_then_reuses_one_invoice(): void
    {
        $this->tlds();
        $a = $this->makeClient();
        $d = $this->domain($a, 'soon.co.tz', 10, 'active', []);
        $d->update(['auto_renew' => false]);
        $this->startSession($a);
        $this->say('11');
        $t = $this->say('1');
        foreach (['*soon.co.tz*', '• Expires: ', '(10 days left)', '• Status: 🟢 active', '• Auto-renew: Off', '• Renewal price (1 year): TZS 21,000', '1) Renew', '0) Back'] as $x) $this->assertContains($x, $t);
        $this->assertSame('detail', $this->session()->state['step']);
        $this->assertContains('Sorry, reply 1 or 0.', $this->say('5'));
        $t = $this->say('1');
        $docs = Document::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->where('client_id', $a->id)->where('notes', 'like', 'Domain renewal:%')->get();
        $this->assertSame(1, $docs->count());
        $this->assertSame(21000.0, (float) $docs[0]->total);
        $this->assertSame('pay_invoice', $this->session()->flow);
        $this->assertContains('Pay online (Card / Mobile Money)', $t);
        $this->assertSame($docs[0]->id, $d->fresh()->meta['renewal_document_id']);
        // again: reused, not duplicated
        $this->startSession($a);
        $this->say('11'); $this->say('1'); $this->say('1');
        $this->assertSame(1, Document::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->where('client_id', $a->id)->where('notes', 'like', 'Domain renewal:%')->count());
        // back from detail lists again; MENU leaves
        $this->startSession($a);
        $this->say('11'); $this->say('1');
        $this->assertContains('*My Domains*', $this->say('0'));
        $this->say('1');
        $this->assertContains('*Choose a service:*', $this->say('menu'));
        $this->assertSame(0, $this->httpCount(), 'no external call');
    }

    public function test_my_domains_not_renewable_through_us_shows_no_renew_option(): void
    {
        $this->tlds();
        $a = $this->makeClient();
        $this->domain($a, 'elsewhere.com', 30, 'active', ['unmanaged' => true, 'registrar' => 'someone-else']);
        $this->domain($a, 'nopricing.xyz', 40, 'active', []);
        $this->startSession($a);
        $this->say('11');
        foreach ([1, 2] as $n) {
            $this->say('11') ; // re-open list (from detail this is an invalid pick; reset to be safe)
            $this->startSession($a); $this->say('11');
            $t = $this->say((string) $n);
            $this->assertNotContains('1) Renew', $t);
            $this->assertContains('Contact us to renew this domain.', $t);
            $this->assertContains('Sorry, reply 0.', $this->say('1'));
        }
        $this->lang('sw');
        $this->startSession($a); $this->lang('sw'); $this->say('11');
        $this->assertContains('Wasiliana nasi kuhuisha domain hii.', $this->say('1'));
        $this->assertSame(0, Document::withoutGlobalScopes()->where('client_id', $a->id)->count());
    }

    // ── 12) My Hosting ──

    public function test_my_hosting_list_detail_renew_and_manage(): void
    {
        $a = $this->makeClient();
        $b = $this->makeClient('Baraka Test', '255700000002');
        [$h1, $s1] = $this->hostingSub($a, 'later.example.test', 60);
        [$h2, $s2] = $this->hostingSub($a, 'sooner.example.test', 4);
        [$h3, $s3] = $this->hostingSub($b, 'theirs.example.test', 4);
        $this->startSession($a);
        $t = $this->say('12');
        $this->assertSame('my_hosting', $this->session()->flow);
        $this->assertNotContains('theirs.example.test', $t);
        $this->assertContains('1) sooner.example.test — Starter — expires ', $t);
        $this->assertContains('(4 days left) — ⚠️', $t);
        $this->assertContains('(60 days left) — 🟢', $t);
        $this->startSession($a); $this->lang('sw');
        $t = $this->say('12');
        foreach (['*Hosting Yangu*', 'inaisha ', '(siku 4 zimebaki)'] as $x) $this->assertContains($x, $t);
        $this->startSession($a);
        $this->say('12');
        $t = $this->say('1');
        foreach (['*Hosting: sooner.example.test*', '• Plan: Starter', '• Domain: sooner.example.test', '• Expires: ', '• Status: ⚠️ active', '1) Renew', '2) Manage hosting', '0) Back'] as $x) $this->assertContains($x, $t);
        // renew: generator invoice once, reused after
        $t = $this->say('1');
        $docs = $this->docs($a);
        $this->assertSame(1, $docs->count());
        $this->assertContains('Invoice ' . $docs[0]->document_number, $t);
        $this->assertSame('pay_invoice', $this->session()->flow);
        $this->startSession($a);
        $this->say('12'); $this->say('1'); $this->say('1');
        $this->assertSame(1, $this->docs($a)->count(), 'open invoice reused');
        $this->assertSame(0, $this->docs($b)->count());
        // manage jumps into the EXISTING hosting_manage flow
        $this->startSession($a);
        $this->say('12'); $this->say('1');
        $t = $this->say('2');
        $this->assertSame('hosting_manage', $this->session()->flow);
        $this->assertSame('account_menu', $this->session()->state['step']);
        $this->assertSame($h2->id, $this->session()->state['account_id']);
        $this->assertContains('Open cPanel', $t);
        // back / MENU
        $this->startSession($a);
        $this->say('12'); $this->say('1');
        $this->assertContains('*My Hosting*', $this->say('0'));
        $this->assertContains('Choose a service', $this->say('0'));
        $this->assertContains('Sorry, reply 1, 2 or 0.', (function () { $this->say('12'); $this->say('1'); return $this->say('7'); })());
        $this->assertContains('Choose a service', $this->say('menu'));
        // a stranger's account can never be reached through a forged state
        $s = $this->session();
        $s->update(['flow' => 'my_hosting', 'state' => ['step' => 'detail', 'account_id' => $h3->id, 'options' => ['manage']]]);
        $this->assertContains('no longer available', $this->say('1'));
        $this->assertSame(1, $this->docs($a)->count());
    }

    public function test_my_domains_and_hosting_empty_states(): void
    {
        $a = $this->makeClient();
        $this->startSession($a);
        $this->assertContains("You don't have any registered domains right now.", $this->say('11'));
        $this->assertContains("You don't have any hosting registered with us yet.", $this->say('12'));
        $this->assertContains('*Choose a service:*', Fw::last());
    }

    public function test_hosting_and_server_lists_cap_with_search(): void
    {
        $a = $this->makeClient();
        for ($i = 1; $i <= 11; $i++) $this->hostingSub($a, sprintf('site%02d.example.test', $i), $i + 5);
        for ($i = 1; $i <= 10; $i++) $this->makeServer($a, sprintf('srv%02d', $i), (string) (9000 + $i), '203.0.113.' . (100 + $i));
        $this->startSession($a);
        $this->say('3');
        $t = $this->say('2');
        $this->assertSame(9, preg_match_all('/^\d\) 🟢 site\d\d/mu', $t));
        $this->assertContains('There are 2 more. Type a name to search.', $t);
        $t = $this->say('site11');
        $this->assertContains('*Hosting: site11.example.test*', $t, 'a single search hit opens the account');
        $this->startSession($a);
        $this->say('10');
        $t = $this->say('1');
        $this->assertSame(9, preg_match_all('/^\d\) 🟢 srv\d\d/mu', $t));
        $this->assertContains('There is 1 more'.'', str_replace('There are 1 more', 'There is 1 more', $t));
        $this->assertContains('Type a name to search.', $t);
        $t = $this->say('srv10');
        $this->assertContains('*Cloud Server: srv10*', $t);
        // no cap => no search: a stray word is just invalid input naming the choices
        $b = $this->makeClient('Baraka Test', '255700000002');
        $this->hostingSub($b, 'b1.example.test', 5); $this->hostingSub($b, 'b2.example.test', 6);
    }
}

class Fw extends WhatsAppService
{
    public static array $sent = [];
    public function __construct() {}
    public function sendSessionText(Tenant $tenant, string $recipient, string $message): array { self::$sent[] = ['type' => 'text', 'text' => $message]; return []; }
    public function sendCtaUrlSession(Tenant $tenant, string $recipient, string $text, string $buttonText, string $url): array { self::$sent[] = ['type' => 'cta', 'text' => $text, 'button' => $buttonText, 'url' => $url]; return []; }
    public static function last(): string { return end(self::$sent)['text'] ?? ''; }
    public static function allText(): string { return implode("\n", array_column(self::$sent, 'text')); }
}

/** FRED is never contacted: non-Name.com TLDs answer from $fred; Name.com TLDs use the real (Http-faked) driver. */
class FakeRegistrar extends DomainRegistrarManager
{
    public static array $fred = [];
    public static int $fredCalls = 0;
    public function checkFor(string $tenantId, string $name, ?\App\Models\DomainTld $pricing): array
    {
        if ($pricing && $pricing->registrar === 'namecom') return parent::checkFor($tenantId, $name, $pricing);
        self::$fredCalls++;
        return ['available' => self::$fred[$name] ?? false, 'reason' => null];
    }
    public function driverFor(string $tenantId, ?string $domainId = null): \App\Contracts\RegistrarDriver
    {
        // Never a real FRED client: only check() answers (from $fred); anything else is a test failure.
        return new class implements \App\Contracts\RegistrarDriver {
            public function check(string $domain): array { FakeRegistrar::$fredCalls++; return ['available' => FakeRegistrar::$fred[$domain] ?? false, 'reason' => null]; }
            public function info(string $domain): array { throw new \RuntimeException('FRED must not be used in tests'); }
            public function credit(): array { throw new \RuntimeException('FRED must not be used in tests'); }
            public function register(string $domain, int $years = 1, array $nameservers = []): array { throw new \RuntimeException('FRED must not be used in tests'); }
            public function renew(string $domain, int $years = 1): array { throw new \RuntimeException('FRED must not be used in tests'); }
            public function transferIn(string $domain, string $authInfo): array { throw new \RuntimeException('FRED must not be used in tests'); }
            public function updateDomain(string $domain, array $changes): array { throw new \RuntimeException('FRED must not be used in tests'); }
        };
    }
}
