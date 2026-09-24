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

        config(['services.mosms.inbound_webhook_secret' => 'test-secret']);
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
        $this->assertContains("Hi {$c->name}! Choose a service:", $t);

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

    public function test_submenu_navigation_and_back(): void
    {
        $c = $this->makeClient();
        $this->startSession($c);
        $t = $this->say('10');
        $this->assertSame('more_services', $this->session()->flow);
        foreach (['1) My Servers', '2) Expiring soon', '0) Back'] as $x) $this->assertContains($x, $t);

        $t = $this->say('9');
        $this->assertContains('Sorry, reply 1, 2 or 0', $t);
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
        foreach (['a-web', 'a-db', '203.0.113.71', 'eu-central', 'running'] as $x) $this->assertContains($x, $t);
        foreach (['b-secret', '203.0.113.73', 'a-cancelled', 'a-gone', 'a-unlinked'] as $x) $this->assertNotContains($x, $t);
        $this->assertSame('pick', $this->session()->state['step']);

        // invalid pick keeps the list state; other numbers fine
        $this->assertContains('valid number', $this->say('5'));
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
            $this->assertContains('valid number', $this->say($bad));
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
        $this->assertSame(10, preg_match_all('/^\d+\) d\d+\.co\.tz/m', $t));
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
        $this->assertContains('Invoice ' . $doc[0]->document_number . ' — TZS 21,000', $t);
        $this->assertContains('Online (Pesapal)', $t);
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
        $this->assertContains('mybiz.com is available! Price: TZS 42,970 for 1 year. Reply YES to order.', $t);
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
        $this->assertContains('Invoice ' . $doc->document_number . ' — TZS 42,970', $t);
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
        $this->assertContains('mybiz.co.tz is available', $this->say('1'));
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
        $this->assertContains('valid number', $this->say('50'));
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
        $this->assertContains('Domain mybiz.co.tz is AVAILABLE! Registration price: TZS 19,999/year. Choose option 1 to order it.', $t);
        // bare label with no fallback possible: polite retry, state kept
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
        throw new \RuntimeException('FRED driver must not be used in tests');
    }
}
