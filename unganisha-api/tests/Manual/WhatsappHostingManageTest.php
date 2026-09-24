<?php

namespace Tests\Manual;

use App\Models\Client;
use App\Models\ClientSubscription;
use App\Models\Document;
use App\Models\Domain;
use App\Models\HostingAccount;
use App\Models\MosmsAccount;
use App\Models\ProductService;
use App\Models\RecurringInvoiceLog;
use App\Models\Server;
use App\Models\Tenant;
use App\Models\User;
use App\Models\WhatsappRenewalSession;
use App\Notifications\HostingUsageWarningNotification;
use App\Services\Hosting\HostingSsoService;
use App\Services\WhatsAppService;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Notification;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Artisan;

/**
 * Standalone check (phpunit is not installed on this server, and the app's
 * migrations are not sqlite-compatible). Runs against the LIVE database inside
 * a transaction that is ALWAYS rolled back. Everything external is faked:
 * WhatsApp (bound fake), WHM (Http::fake + fake SSO service), notifications.
 *
 *   php tests/Manual/run_whatsapp_hosting_manage.php
 */
class WhatsappHostingManageTest
{
    public $app;
    private function fail(string $m): void { throw new \RuntimeException($m); }
    public function assertSame($e, $a): void { if ($e !== $a) $this->fail('expected ' . var_export($e, true) . ' got ' . var_export($a, true)); }
    public function assertTrue($c, string $m = 'not true'): void { if (!$c) $this->fail($m); }
    public function assertNull($v): void { if ($v !== null) $this->fail('expected null'); }
    public function assertNotNull($v): void { if ($v === null) $this->fail('expected not null'); }
    public function assertStringContainsString($n, $h): void { if (!str_contains($h, $n)) $this->fail("missing '$n' in:\n$h"); }
    public function assertStringNotContainsString($n, $h): void { if (str_contains($h, $n)) $this->fail("unexpected '$n' in:\n$h"); }
    public function assertSameCount(int $e, int $a): void { $this->assertSame($e, $a); }

    private Tenant $tenant;
    private User $user;
        private string $phone;
    private string $rawPhone;

    public function setUp(): void
    {
        $this->app = app();
        $this->rawPhone = '255700000001';
        $this->phone = \App\Helpers\PhoneHelper::normalize($this->rawPhone);
        DB::beginTransaction();

        $this->tenant = Tenant::withoutGlobalScopes()->where('name', 'MoBilling Test Co')->firstOrFail();
        $this->user = User::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->firstOrFail();
        auth()->login($this->user);

        config(['services.mosms.inbound_webhook_secret' => 'test-secret', 'services.mosms.inbound_rate_limit' => 100000]);
        MosmsAccount::create(['tenant_id' => $this->tenant->id, 'mosms_tenant_id' => 987654321, 'email' => 'x@example.test', 'token' => 'x', 'sender' => 'x']);

        Http::fake();
        Notification::fake();

        FakeWa::$sent = [];
        $this->app->bind(WhatsAppService::class, fn () => new FakeWa());
    }

    public function tearDown(): void
    {
        DB::rollBack();
    }

    // ── helpers ──
    private function makeClient(string $name = 'Asha Test', ?string $phone = null): Client
    {
        return Client::create(['tenant_id' => $this->tenant->id, 'name' => $name, 'phone' => $phone ?? $this->rawPhone, 'email' => strtolower(str_replace(' ', '', $name)) . '@example.test', 'status' => 'active']);
    }

    private function makeHosting(Client $client, string $domain, string $status = 'active', array $meta = []): HostingAccount
    {
        $server = Server::withoutGlobalScopes()->first() ?? Server::create(['tenant_id' => $this->tenant->id, 'name' => 'fake', 'hostname' => 'fake.invalid', 'port' => 2087, 'username' => 'root', 'api_token' => 'x', 'type' => 'whm', 'is_active' => false]);
        $product = ProductService::create(['tenant_id' => $this->tenant->id, 'type' => 'service', 'name' => 'Test Plan', 'price' => 10000, 'category' => 'Web Hosting', 'billing_cycle' => 'yearly', 'provisioning_type' => 'whm_cpanel']);
        $sub = ClientSubscription::create(['tenant_id' => $this->tenant->id, 'client_id' => $client->id, 'product_service_id' => $product->id, 'start_date' => now()->subMonths(6), 'expire_date' => now()->addMonths(6), 'status' => $status === 'active' ? 'active' : 'suspended']);

        return HostingAccount::create(['tenant_id' => $this->tenant->id, 'client_subscription_id' => $sub->id, 'server_id' => $server->id, 'domain' => $domain, 'cpanel_username' => substr(str_replace('.', '', $domain), 0, 8), 'package' => 'Starter', 'status' => $status, 'last_synced_at' => now()->subHours(3), 'meta' => $meta]);
    }

    private function startSession(Client $client, ?string $flow = null, ?string $assistedBy = null): void
    {
        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $this->tenant->id, 'phone' => $this->phone],
            ['client_id' => $client->id, 'assisted_by_user_id' => $assistedBy, 'flow' => $flow, 'state' => null, 'items' => null, 'language' => 'en', 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(30)],
        );
    }

    private function say(string $text): void
    {
        $req = Request::create('/api/webhooks/mosms/menu', 'POST', ['secret' => 'test-secret', 'mosms_tenant_id' => 987654321, 'phone' => $this->rawPhone, 'text' => $text], [], [], ['HTTP_ACCEPT' => 'application/json']);
        $res = app()->handle($req);
        $this->assertSame(200, $res->getStatusCode());
    }

    private function session(): ?WhatsappRenewalSession
    {
        return WhatsappRenewalSession::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->where('phone', $this->phone)->first();
    }

    private function allText(): string
    {
        return implode("\n---\n", array_column(FakeWa::$sent, 'text'));
    }

    private function unpaidInvoice(Client $client, HostingAccount $acct, string $no, float $total = 50000, string $status = 'overdue'): Document
    {
        $doc = Document::create(['tenant_id' => $this->tenant->id, 'client_id' => $client->id, 'type' => 'invoice', 'document_number' => $no, 'date' => now()->subDays(20), 'due_date' => now()->subDays(5), 'subtotal' => $total, 'total' => $total, 'status' => $status]);
        RecurringInvoiceLog::create(['tenant_id' => $this->tenant->id, 'client_id' => $client->id, 'product_service_id' => $acct->subscription->product_service_id, 'client_subscription_id' => $acct->client_subscription_id, 'document_id' => $doc->id, 'next_bill_date' => now()->addDays(random_int(1, 300))]);
        return $doc;
    }

    // ── tests ──
    public function test_submenu_routes_to_order_flow_and_hosting_manage(): void
    {
        $client = $this->makeClient();
        $this->makeHosting($client, 'aaa.example.test');

        $this->startSession($client);
        $this->say('3');
        $this->assertSame('hosting_submenu', $this->session()->flow);
        $this->say('1');
        $this->assertSame('order_hosting', $this->session()->flow);

        $this->startSession($client);
        $this->say('3');
        $this->say('2');
        $this->assertSame('hosting_manage', $this->session()->flow);
    }

    public function test_single_account_skips_pick_step_and_multi_account_asks(): void
    {
        $client = $this->makeClient();
        $this->makeHosting($client, 'one.example.test');
        $this->startSession($client);
        $this->say('3'); $this->say('2');
        $this->assertSame('account_menu', $this->session()->state['step']);
        $this->assertStringContainsString('one.example.test', $this->allText());

        FakeWa::$sent = [];
        $this->makeHosting($client, 'two.example.test', 'suspended');
        $this->startSession($client);
        $this->say('3'); $this->say('2');
        $this->assertSame('pick_account', $this->session()->state['step']);
        $this->assertStringContainsString('1) 🟢 one.example.test', $this->allText());
        $this->assertStringContainsString('2) 🔴 two.example.test', $this->allText());
        $this->say('1');
        $this->assertSame('account_menu', $this->session()->state['step']);
    }

    public function test_status_text_uses_stored_values_only(): void
    {
        $client = $this->makeClient();
        $this->makeHosting($client, 'stat.example.test', 'active', ['disk_used' => '2048M', 'disk_limit' => '4096M', 'plan' => 'Starter']);
        Domain::create(['tenant_id' => $this->tenant->id, 'client_id' => $client->id, 'name' => 'stat.example.test', 'status' => 'active', 'expires_at' => '2027-03-01', 'meta' => ['ssl_valid' => true, 'ssl_expires_at' => '2026-12-31']]);
        $this->startSession($client);
        $this->say('3'); $this->say('2');
        $t = $this->allText();
        $this->assertStringContainsString('2048M / 4096M', $t);
        $this->assertStringContainsString('█████░░░░░ 50%', $t);
        $this->assertStringContainsString('01 Mar 2027', $t);
        $this->assertStringContainsString('31 Dec 2026', $t);
        $this->assertStringContainsString('Last synced', $t);
        $this->assertStringNotContainsString('andwidth', $t);

        // No usage / SSL stored -> nothing invented
        FakeWa::$sent = [];
        $client2 = $this->makeClient('Bahati Test', '255700000002');
        $this->makeHosting($client2, 'bare.example.test', 'active', []);
        $this->startSession($client2);
        $this->say('3'); $this->say('2');
        $t = $this->allText();
        $this->assertStringNotContainsString('Disk', $t);
        $this->assertStringNotContainsString('SSL', $t);
    }

    public function test_suspended_lists_unpaid_invoices_and_hands_off_to_offer_payment(): void
    {
        $client = $this->makeClient();
        $acct = $this->makeHosting($client, 'susp.example.test', 'suspended');
        $inv = $this->unpaidInvoice($client, $acct, 'INV-TX-1', 50000);
        $this->unpaidInvoice($client, $acct, 'INV-TX-PAID', 20000, 'paid');
        $other = $this->makeClient('Other Person', '255700000009');
        Document::create(['tenant_id' => $this->tenant->id, 'client_id' => $other->id, 'type' => 'invoice', 'document_number' => 'INV-TX-OTHER', 'date' => now(), 'due_date' => now(), 'subtotal' => 1, 'total' => 1, 'status' => 'sent']);

        $this->startSession($client);
        $this->say('3'); $this->say('2');
        $t = $this->allText();
        $this->assertStringContainsString('suspended', $t);
        $this->assertStringContainsString('INV-TX-1', $t);
        $this->assertStringNotContainsString('INV-TX-PAID', $t);
        $this->assertStringNotContainsString('INV-TX-OTHER', $t);

        $this->say('1');
        $s = $this->session();
        $this->assertSame('pay_invoice', $s->flow);
        $this->assertSame($inv->id, $s->state['document_id']);
    }

    public function test_suspended_without_invoice_is_honest_and_offers_support(): void
    {
        $client = $this->makeClient();
        $this->makeHosting($client, 'nodebt.example.test', 'suspended');
        $this->startSession($client);
        $this->say('3'); $this->say('2');
        $this->assertStringContainsString("don't see any known unpaid invoice", $this->allText());
        $this->assertSame(['support'], $this->session()->state['options']);
        $this->say('1');
        $this->assertSame('ask_ticket_text', $this->session()->state['step']);
        $this->say('Nimelipa lakini bado imesimama');
        $this->assertStringContainsString('TKT-', $this->allText());
    }

    public function test_cpanel_link_sent_for_client_but_never_in_staff_assist(): void
    {
        $this->app->bind(HostingSsoService::class, fn () => new class extends HostingSsoService {
            public function cpanelUrl(HostingAccount $account): string { return 'https://fake.invalid/cpsess123/login'; }
        });
        $client = $this->makeClient();
        $this->makeHosting($client, 'cp.example.test', 'active');

        $this->startSession($client);
        $this->say('3'); $this->say('2'); $this->say('1');
        $cta = collect(FakeWa::$sent)->firstWhere('type', 'cta');
        $this->assertNotNull($cta);
        $this->assertSame('Open cPanel', $cta['button']);

        FakeWa::$sent = [];
        $this->startSession($client, null, $this->user->id);
        $this->say('3'); $this->say('2'); $this->say('1');
        $this->assertNull(collect(FakeWa::$sent)->firstWhere('type', 'cta'));
        $this->assertStringNotContainsString('fake.invalid', $this->allText());
        $this->assertStringContainsString('admin panel', $this->allText());
    }

    public function test_client_cannot_see_another_clients_hosting_or_deleted_client(): void
    {
        $a = $this->makeClient('Client A', '255700000001');
        $b = $this->makeClient('Client B', '255700000003');
        $this->makeHosting($a, 'a-site.example.test');
        $this->makeHosting($b, 'b-site.example.test');

        $this->startSession($a);
        $this->say('3'); $this->say('2');
        $this->assertStringContainsString('a-site.example.test', $this->allText());
        $this->assertStringNotContainsString('b-site.example.test', $this->allText());

        // Soft-deleted client's session is rejected entirely
        FakeWa::$sent = [];
        $b->delete();
        $this->startSession($b);
        $this->say('3');
        $this->assertStringNotContainsString('b-site.example.test', $this->allText());
        $this->assertNull($this->session());
    }

    // ── extended account menu (upgrade / email / ticket / connect domain) ──
    private function plan(string $name, float $price, array $o = []): ProductService
    {
        return ProductService::create(array_merge(['tenant_id' => $this->tenant->id, 'type' => 'service', 'name' => $name, 'price' => $price, 'category' => 'Web Hosting', 'billing_cycle' => 'yearly', 'provisioning_type' => 'whm_cpanel', 'is_active' => true, 'portal_visible' => true, 'cpanel_package' => 'pkg_' . strtolower($name), 'description' => 'spec of ' . $name], $o));
    }

    private function openMenu(Client $client, ?string $assistedBy = null): void
    {
        $this->startSession($client, null, $assistedBy);
        $this->say('3'); $this->say('2');
    }

    private function bindFakes(): void
    {
        FakeEmail::$created = []; FakeEmail::$limit = null; FakeEmail::$count = 0;
        $this->app->bind(\App\Services\Hosting\HostingEmailService::class, fn () => new FakeEmail());
        $this->app->bind(HostingSsoService::class, fn () => new class extends HostingSsoService {
            public function cpanelUrl(HostingAccount $account): string { return 'https://fake.invalid/cpsess/login'; }
            public function cpanelUrlTo(HostingAccount $account, string $goto): string { return 'https://fake.invalid/cpsess/login?goto_uri=' . urlencode($goto); }
        });
    }

    public function test_upgrade_list_only_higher_priced_same_category_visible_active(): void
    {
        $client = $this->makeClient();
        $acct = $this->makeHosting($client, 'up.example.test');   // Test Plan 10000 Web Hosting yearly
        $this->plan('UpHigh', 30000);
        $this->plan('UpLow', 5000);
        $this->plan('UpSame', 10000);
        $this->plan('UpHidden', 40000, ['portal_visible' => false]);
        $this->plan('UpInactive', 40000, ['is_active' => false]);
        $this->plan('UpOtherCat', 40000, ['category' => 'Email']);
        $this->plan('UpMonthly', 40000, ['billing_cycle' => 'monthly']);
        $this->plan('UpNoWhm', 40000, ['provisioning_type' => 'none']);

        $this->openMenu($client);
        $this->assertSame(['cpanel', 'upgrade', 'email', 'connect', 'support', 'resetpass'], $this->session()->state['options']);
        FakeWa::$sent = [];
        $this->say('2');
        $t = $this->allText();
        $this->assertStringContainsString('UpHigh', $t);
        $this->assertStringContainsString('spec of UpHigh', $t);
        foreach (['UpLow', 'UpSame', 'UpHidden', 'UpInactive', 'UpOtherCat', 'UpMonthly', 'UpNoWhm'] as $bad) {
            $this->assertStringNotContainsString($bad, $t);
        }
        $this->assertSame('upgrade_pick', $this->session()->state['step']);
    }

    private function doUpgrade(Client $client, ProductService $plan): Document
    {
        $this->openMenu($client);
        $this->say('2'); $this->say('1'); $this->say('NDIYO');
        $this->assertSame('pay_invoice', $this->session()->flow);
        return Document::withoutGlobalScopes()->findOrFail($this->session()->state['document_id']);
    }

    public function test_upgrade_creates_invoice_and_marker_but_changes_nothing_until_paid_then_applies_once(): void
    {
        \Illuminate\Support\Facades\Bus::fake();
        $client = $this->makeClient();
        $acct = $this->makeHosting($client, 'up2.example.test');
        $sub = $acct->subscription;
        $oldProduct = $sub->product_service_id;
        $new = $this->plan('UpNew', 30000);

        $doc = $this->doUpgrade($client, $new);
        $this->assertSame('invoice', $doc->type);
        $this->assertSame('sent', $doc->status);
        $this->assertSame($client->id, $doc->client_id);
        $this->assertTrue(str_starts_with($doc->notes, 'Upgrade: Test Plan → UpNew — up2.example.test'), $doc->notes);
        $this->assertTrue((float) $doc->total > 0 && (float) $doc->total <= 20000, 'prorated charge <= full difference');

        $sub->refresh();
        $this->assertSame($oldProduct, $sub->product_service_id);
        $this->assertSame($new->id, $sub->metadata['pending_plan_change']['product_service_id']);
        $this->assertSame($doc->id, $sub->metadata['pending_plan_change']['document_id']);
        $this->assertSame(0, \Illuminate\Support\Facades\Bus::dispatched(\App\Jobs\Hosting\ChangeHostingPackage::class)->count());

        // pay -> DocumentObserver applies via PlanChangeService
        $doc->update(['status' => 'paid']);
        $sub->refresh();
        $this->assertSame($new->id, $sub->product_service_id);
        $this->assertTrue(!isset($sub->metadata['pending_plan_change']));
        $this->assertSame(1, \Illuminate\Support\Facades\Bus::dispatched(\App\Jobs\Hosting\ChangeHostingPackage::class)->count());

        // double fire is a no-op
        $doc->refresh();
        (new \App\Observers\DocumentObserver())->updated($doc->setAttribute('status', 'paid'));
        $this->assertSame(1, \Illuminate\Support\Facades\Bus::dispatched(\App\Jobs\Hosting\ChangeHostingPackage::class)->count());
        $this->assertSame($new->id, $sub->fresh()->product_service_id);
    }

    public function test_upgrade_requires_ndiyo_and_creates_no_invoice_otherwise(): void
    {
        $client = $this->makeClient();
        $acct = $this->makeHosting($client, 'up3.example.test');
        $this->plan('UpNew3', 30000);
        $before = Document::withoutGlobalScopes()->where('client_id', $client->id)->count();
        $this->openMenu($client);
        $this->say('2'); $this->say('1');
        $this->assertSame('upgrade_confirm', $this->session()->state['step']);
        $this->say('hapana');
        $this->assertSame($before, Document::withoutGlobalScopes()->where('client_id', $client->id)->count());
        $this->assertTrue(!isset($acct->subscription->fresh()->metadata['pending_plan_change']));
    }

    public function test_email_create_validates_never_exposes_password_and_sso_only_in_client_session(): void
    {
        $this->bindFakes();
        $client = $this->makeClient();
        $this->makeHosting($client, 'mail.example.test');

        $this->openMenu($client);
        $this->say('3');            // email menu
        $this->say('1');            // create
        foreach (['Bad Name', 'a@b.com', str_repeat('a', 33), '.dot', 'a..b'] as $bad) {
            $this->say($bad);
        }
        $this->assertSame([], FakeEmail::$created);
        $this->say('Info.Sales');
        $this->assertSame(1, count(FakeEmail::$created));
        [$local, $domain, $pw] = FakeEmail::$created[0];
        $this->assertSame('info.sales', $local);
        $this->assertSame('mail.example.test', $domain);
        $this->assertTrue(strlen($pw) >= 20);
        $t = $this->allText();
        $this->assertStringNotContainsString($pw, $t);
        $cta = collect(FakeWa::$sent)->firstWhere('type', 'cta');
        $this->assertNotNull($cta);
        $this->assertStringContainsString('email_accounts', $cta['url']);
        $this->assertStringContainsString('set your own password', $cta['text']);
        $this->assertStringNotContainsString($pw, json_encode(FakeWa::$sent));
    }

    public function test_email_limit_respected_forgot_password_link_and_assist_or_inactive_blocked(): void
    {
        $this->bindFakes();
        $client = $this->makeClient();
        $this->makeHosting($client, 'lim.example.test');

        FakeEmail::$limit = 2; FakeEmail::$count = 2;
        $this->openMenu($client);
        $this->say('3'); $this->say('1'); $this->say('newbox');
        $this->assertSame([], FakeEmail::$created);
        $this->assertStringContainsString('email limit', $this->allText());

        // forgot -> SSO link, no reset performed
        FakeWa::$sent = [];
        $this->openMenu($client);
        $this->say('3'); $this->say('2');
        $this->assertNotNull(collect(FakeWa::$sent)->firstWhere('type', 'cta'));
        $this->assertSame([], FakeEmail::$created);

        // staff assist: blocked, no link
        FakeWa::$sent = [];
        $this->openMenu($client, $this->user->id);
        $this->say('3');
        $this->assertNull(collect(FakeWa::$sent)->firstWhere('type', 'cta'));
        $this->assertStringContainsString('staff-assist', $this->allText());
        $this->assertNull($this->session()->state['step'] === 'email_menu' ? true : null);

        // suspended account: no email option at all
        $c2 = $this->makeClient('Susp Owner', '255700000005');
        $this->makeHosting($c2, 'sus.example.test', 'suspended');
        $this->openMenu($c2);
        $this->assertTrue(!in_array('email', $this->session()->state['options'], true));
    }

    public function test_ticket_creation_and_rate_limit(): void
    {
        $client = $this->makeClient();
        $this->makeHosting($client, 'tk.example.test');
        for ($i = 1; $i <= 3; $i++) {
            \Illuminate\Support\Carbon::setTestNow(now()->addSeconds(5));
            $this->openMenu($client);
            $this->say('5');
            $this->assertSame('ask_ticket_text', $this->session()->state['step']);
            $this->say('Website yangu ina hitilafu namba ' . $i);
        }
        $this->assertSame(3, \App\Models\Ticket::withoutGlobalScopes()->where('client_id', $client->id)->count());
        $this->assertStringContainsString('TKT-', $this->allText());

        FakeWa::$sent = [];
        \Illuminate\Support\Carbon::setTestNow(now()->addSeconds(5));
        $this->openMenu($client);
        $this->say('5');
        $this->assertStringContainsString('several support requests', $this->allText());
        $this->assertSame(3, \App\Models\Ticket::withoutGlobalScopes()->where('client_id', $client->id)->count());

        // >500 chars rejected (fresh client so limit not hit)
        $c2 = $this->makeClient('Ticket Two', '255700000006');
        $this->makeHosting($c2, 'tk2.example.test');
        $this->openMenu($c2);
        $this->say('5');
        $this->say(str_repeat('x', 501));
        $this->assertSame(0, \App\Models\Ticket::withoutGlobalScopes()->where('client_id', $c2->id)->count());
        $this->assertSame('ask_ticket_text', $this->session()->state['step']);
        \Illuminate\Support\Carbon::setTestNow();
    }

    public function test_connect_domain_prefills_change_dns_only_for_own_domain_and_requires_ndiyo(): void
    {
        $client = $this->makeClient();
        $dnsAcct = $this->makeHosting($client, 'dns.example.test', 'active', ['ip' => '203.0.113.9']);
        $srv = Server::create(['tenant_id' => $this->tenant->id, 'name' => 'dnssrv', 'hostname' => 'dns-fake.invalid', 'port' => 2087, 'username' => 'root', 'api_token' => 'x', 'type' => 'whm', 'is_active' => false, 'nameservers' => ['ns1.host.test', 'ns2.host.test']]);
        HostingAccount::withoutGlobalScopes()->whereKey($dnsAcct->id)->update(['server_id' => $srv->id]);
        $d = Domain::create(['tenant_id' => $this->tenant->id, 'client_id' => $client->id, 'name' => 'dns.example.test', 'status' => 'active', 'meta' => ['unmanaged' => true]]);

        $this->openMenu($client);
        $this->say('4');
        $t = $this->allText();
        $this->assertStringContainsString('ns1.host.test, ns2.host.test', $t);
        $this->assertStringContainsString('203.0.113.9', $t);
        $s = $this->session();
        $this->assertSame('change_dns', $s->flow);
        $this->assertSame('confirm', $s->state['step']);
        $this->assertSame($d->id, $s->state['domain_id']);
        $this->assertSame(['ns1.host.test', 'ns2.host.test'], $s->state['nameservers']);

        // anything but NDIYO cancels, domain untouched
        $this->say('hapana');
        $this->assertNull(Domain::withoutGlobalScopes()->find($d->id)->meta['pending_nameserver_request'] ?? null);

        // NDIYO goes through the existing flow (unmanaged -> manual staff request, no registrar call)
        $this->openMenu($client);
        $this->say('4'); $this->say('NDIYO');
        $this->assertSame(['ns1.host.test', 'ns2.host.test'], Domain::withoutGlobalScopes()->find($d->id)->meta['pending_nameserver_request']['nameservers']);

        // domain NOT with this client (another client owns it): info only, no handoff
        FakeWa::$sent = [];
        $c2 = $this->makeClient('Ext Owner', '255700000007');
        $this->makeHosting($c2, 'ext.example.test', 'active', ['ip' => '203.0.113.10']);
        $this->openMenu($c2);
        $this->say('4');
        $this->assertStringContainsString('not registered with us', $this->allText());
        $this->assertSame('hosting_manage', $this->session()->flow);
    }

    public function test_client_a_cannot_touch_client_b_account_via_forged_state(): void
    {
        $this->bindFakes();
        $a = $this->makeClient('Client A2', '255700000001');
        $b = $this->makeClient('Client B2', '255700000003');
        $this->makeHosting($a, 'a2.example.test');
        $acctB = $this->makeHosting($b, 'b2.example.test');
        $this->plan('UpNewB', 30000);

        foreach (['ask_email_name' => 'hack', 'ask_ticket_text' => 'hello there', 'upgrade_confirm' => 'NDIYO'] as $step => $text) {
            $this->startSession($a);
            WhatsappRenewalSession::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->where('phone', $this->phone)
                ->update(['flow' => 'hosting_manage', 'state' => ['step' => $step, 'account_id' => $acctB->id, 'plan_id' => ProductService::where('name', 'UpNewB')->value('id')]]);
            $this->say($text);
        }
        $this->assertSame([], FakeEmail::$created);
        $this->assertSame(0, \App\Models\Ticket::withoutGlobalScopes()->where('related_service', 'b2.example.test')->count());
        $this->assertTrue(!isset($acctB->subscription->fresh()->metadata['pending_plan_change']));
        $this->assertSame(0, Document::withoutGlobalScopes()->where('client_id', $a->id)->count());
    }

    public function test_usage_warning_command_sends_once_per_threshold(): void
    {
        $client = $this->makeClient();
        $acct = $this->makeHosting($client, 'warn.example.test', 'active', ['disk_used' => '3500M', 'disk_limit' => '4096M']);
        Server::withoutGlobalScopes()->whereKey($acct->server_id)->update(['is_active' => true]);

        $this->assertSame(0, Artisan::call('hosting:send-usage-warnings', ['--account' => $acct->id]));
        $this->assertSame(1, Notification::sent($client, HostingUsageWarningNotification::class)->count());

        $this->assertSame(0, Artisan::call('hosting:send-usage-warnings', ['--account' => $acct->id]));
        $this->assertSame(1, Notification::sent($client, HostingUsageWarningNotification::class)->count());

        // Crossing 100% is a new threshold -> one more
        $acct->refresh();
        $acct->update(['meta' => array_merge($acct->meta, ['disk_used' => '4096M'])]);
        $this->assertSame(0, Artisan::call('hosting:send-usage-warnings', ['--account' => $acct->id]));
        $this->assertSame(2, Notification::sent($client, HostingUsageWarningNotification::class)->count());
    }
}

class FakeWa extends WhatsAppService
{
    public static array $sent = [];
    public function __construct() {}
    public function sendSessionText(Tenant $tenant, string $recipient, string $message): array
    {
        self::$sent[] = ['type' => 'text', 'text' => $message];
        return [];
    }
    public function sendCtaUrlSession(Tenant $tenant, string $recipient, string $text, string $buttonText, string $url): array
    {
        self::$sent[] = ['type' => 'cta', 'text' => $text, 'button' => $buttonText, 'url' => $url];
        return [];
    }
}

class FakeEmail extends \App\Services\Hosting\HostingEmailService
{
    public static array $created = [];
    public static ?int $limit = null;
    public static int $count = 0;
    public function usage(HostingAccount $account): array { return ['count' => self::$count, 'limit' => self::$limit]; }
    public function create(HostingAccount $account, string $localPart, string $password, int $quotaMb = 1024): void
    {
        self::$created[] = [$localPart, $account->domain, $password];
    }
}
