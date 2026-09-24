<?php

namespace Tests\Manual;

use App\Models\Client;
use App\Models\ClientCredit;
use App\Models\Coupon;
use App\Models\CouponRedemption;
use App\Models\Document;
use App\Models\MosmsAccount;
use App\Models\PaymentIn;
use App\Models\PesapalInvoicePayment;
use App\Models\ProductService;
use App\Models\Tenant;
use App\Models\User;
use App\Models\WhatsappRenewalSession;
use App\Services\CouponService;
use App\Services\WhatsAppService;
use Illuminate\Http\Client\Factory;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Notification;

/**
 * Phase 3: More-services items 4/5/6, status lines, STOP/START, shared phone, suspended client, picker, idempotency, log redaction.
 * Live DB inside an ALWAYS-rolled-back transaction; WhatsApp behind a recording fake; every HTTP call faked
 * with preventStrayRequests.   php tests/Manual/run_whatsapp_phase3.php [name-filter]
 */
class WhatsappPhase3Test
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

    public function setUp(): void
    {
        $this->phone = \App\Helpers\PhoneHelper::normalize($this->rawPhone);
        DB::beginTransaction();
        config(['cache.default' => 'array']); // never poison the real cache (Pesapal token etc.)
        $this->tenant = Tenant::withoutGlobalScopes()->where('name', 'MoBilling Test Co')->firstOrFail();
        $this->user = User::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->firstOrFail();
        auth()->login($this->user);
        config(['services.mosms.inbound_webhook_secret' => 'test-secret', 'services.mosms.inbound_rate_limit' => 100000, 'services.mosms.duplicate_window' => 0]);
        MosmsAccount::create(['tenant_id' => $this->tenant->id, 'mosms_tenant_id' => 987654321, 'email' => 'x@example.test', 'token' => 'x', 'sender' => 'x']);
        $this->fk([]);
        Notification::fake();
        Fw::$sent = [];
        app()->bind(WhatsAppService::class, fn () => new Fw());
    }

    public function tearDown(): void { DB::rollBack(); }

    // ── helpers ──
    private function fk($x): void { Http::swap(new Factory()); Http::preventStrayRequests(); Http::fake($x); }

    private function makeClient(string $name = 'Asha Test', ?string $phone = null): Client
    {
        return Client::create(['tenant_id' => $this->tenant->id, 'name' => $name, 'phone' => $phone ?? $this->rawPhone, 'email' => strtolower(str_replace(' ', '', $name)) . '@example.test', 'status' => 'active']);
    }

    private function makeInvoice(Client $c, float $total = 50000, string $status = 'sent', ?string $notes = null): Document
    {
        static $n = 0;
        $d = Document::withoutGlobalScopes()->create([
            'tenant_id' => $this->tenant->id, 'client_id' => $c->id, 'type' => 'invoice',
            'document_number' => 'P2-' . (++$n) . '-' . substr(uniqid(), -5), 'date' => now()->toDateString(), 'due_date' => now()->addDays(7)->toDateString(),
            'subtotal' => $total, 'discount_amount' => 0, 'tax_amount' => 0, 'total' => $total, 'status' => $status, 'notes' => $notes,
        ]);
        return $d;
    }

    private function say(string $text, ?string $rawPhone = null): string
    {
        $before = count(Fw::$sent);
        $req = Request::create('/api/webhooks/mosms/menu', 'POST', ['secret' => 'test-secret', 'mosms_tenant_id' => 987654321, 'phone' => $rawPhone ?? $this->rawPhone, 'text' => $text], [], [], ['HTTP_ACCEPT' => 'application/json']);
        $res = app()->handle($req);
        $this->assertSame(200, $res->getStatusCode());
        return implode("\n---\n", array_column(array_slice(Fw::$sent, $before), 'text'));
    }

    private function session(): ?WhatsappRenewalSession
    {
        return WhatsappRenewalSession::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->where('phone', $this->phone)->first();
    }

    /** A verified client session (root menu state). */
    private function startSession(Client $client, ?string $assistedBy = null): void
    {
        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $this->tenant->id, 'phone' => $this->phone],
            ['client_id' => $client->id, 'assisted_by_user_id' => $assistedBy, 'flow' => null, 'state' => null, 'items' => null, 'language' => 'en', 'confirmed_at' => now(), 'expires_at' => $assistedBy ? now()->addHours(2) : now()->addDays(30), 'flow_expires_at' => null],
        );
    }

    /** An unverified session waiting for the surname. */
    private function startVerify(Client $client): void
    {
        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $this->tenant->id, 'phone' => $this->phone],
            ['client_id' => $client->id, 'flow' => null, 'state' => ['step' => 'surname'], 'items' => null, 'language' => 'en', 'confirmed_at' => null, 'attempts' => 0, 'expires_at' => now()->addMinutes(10)],
        );
    }

    private function hit(string $route, string $text): string
    {
        $before = count(Fw::$sent);
        $req = Request::create("/api/webhooks/mosms/$route", 'POST', ['secret' => 'test-secret', 'mosms_tenant_id' => 987654321, 'phone' => $this->rawPhone, 'text' => $text], [], [], ['HTTP_ACCEPT' => 'application/json']);
        $res = app()->handle($req);
        $this->assertSame(200, $res->getStatusCode());
        return implode("\n---\n", array_column(array_slice(Fw::$sent, $before), 'text'));
    }

    /** RenewalBundleService that never touches cPanel/registrars: bills a fixed invoice and records which domains were asked. */
    private function fakeBundler(Client $c): void
    {
        $doc = $this->makeInvoice($c, 25000, 'sent', 'Renewal');
        FakeBundler::$asked = [];
        FakeBundler::$doc = $doc;
        app()->bind(\App\Services\Hosting\RenewalBundleService::class, fn () => new FakeBundler());
    }

    public function checkNeutral(): void
    {
        foreach (Fw::$sent as $m) {
            foreach (['name.com', 'namecom', 'linode', 'usd', '$'] as $bad) {
                if (str_contains(strtolower($m['text']), $bad)) $this->fail("supplier/cost leak '$bad' in reply:\n{$m['text']}");
            }
        }
    }

    // ═══ A6: language switch ═══
    public function test_a6_language_switch_en_to_sw_keeps_login(): void
    {
        $c = $this->makeClient();
        $this->startSession($c);
        $this->say('10');
        $r = $this->say('6');
        $this->assertContains('Switch to Kiswahili?', $r);
        $this->assertContains('1) Yes', $r);
        $r = $this->say('1');
        $this->assertContains('Chagua huduma', $r);
        $this->assertContains('Sawa', $r);
        $s = $this->session();
        $this->assertSame('sw', $s->language);
        $this->assertTrue($s->confirmed_at !== null, 'still logged in');
        $this->assertSame($c->id, $s->client_id);
    }

    public function test_a6_language_switch_sw_to_en_and_decline(): void
    {
        $c = $this->makeClient();
        $this->startSession($c);
        $this->session()->update(['language' => 'sw']);
        $this->say('10');
        $r = $this->say('6');
        $this->assertContains('Badilisha kuwa English?', $r);
        $r = $this->say('2');
        $this->assertContains('Huduma Zaidi', $r);
        $this->assertSame('sw', $this->session()->language);
        $this->say('6');
        $r = $this->say('hapana kabisa');
        $this->assertContains('jibu 1 au 2', $r);
        $r = $this->say('1');
        $this->assertContains('Choose a service', $r);
        $this->assertSame('en', $this->session()->language);
    }

    public function test_a6_language_back_and_menu(): void
    {
        $c = $this->makeClient();
        $this->startSession($c);
        $this->say('10');
        $this->say('6');
        $this->assertContains('More services', $this->say('0'));
        $this->say('6');
        $this->assertContains('Choose a service', $this->say('MENU'));
        $this->assertSame('en', $this->session()->language);
    }

    // ═══ shared order helpers ═══
    private function pendingDomainOrder(Client $c, string $name = 'p3-new.test', float $total = 25000, string $action = 'register'): array
    {
        $doc = $this->makeInvoice($c, $total, 'sent', "Domain registration (WhatsApp order): $name (1 year)");
        $d = \App\Models\Domain::create(['tenant_id' => $this->tenant->id, 'client_id' => $c->id, 'name' => $name, 'status' => 'pending', 'auto_renew' => false, 'meta' => ['pending_action' => $action, 'pending_years' => 1, 'order_document_id' => $doc->id, 'unmanaged' => true]]);
        return [$doc, $d];
    }

    private function pendingHostingOrder(Client $c, string $domain = 'p3-host.test', float $total = 60000): array
    {
        $plan = ProductService::create(['tenant_id' => $this->tenant->id, 'type' => 'service', 'name' => 'Starter Plan', 'price' => $total, 'tax_percent' => 0, 'unit' => 'pcs', 'category' => 'Web Hosting', 'billing_cycle' => 'yearly', 'provisioning_type' => 'whm_cpanel']);
        $sub = \App\Models\ClientSubscription::create(['tenant_id' => $this->tenant->id, 'client_id' => $c->id, 'product_service_id' => $plan->id, 'label' => $domain, 'quantity' => 1, 'start_date' => now()->toDateString(), 'status' => 'pending']);
        $doc = $this->makeInvoice($c, $total, 'sent', "Starter Plan (WhatsApp order): $domain");
        \App\Models\RecurringInvoiceLog::create(['tenant_id' => $this->tenant->id, 'client_id' => $c->id, 'client_subscription_id' => $sub->id, 'product_service_id' => $plan->id, 'document_id' => $doc->id, 'next_bill_date' => now()->toDateString()]);
        return [$doc, $sub];
    }

    // ═══ A4: My orders ═══
    public function test_a4_lists_pending_domain_and_hosting_orders_with_details(): void
    {
        $c = $this->makeClient();
        $this->startSession($c);
        [$dd] = $this->pendingDomainOrder($c, 'p3-new.test', 25000);
        [$hd] = $this->pendingHostingOrder($c, 'p3-host.test', 60000);
        $this->say('10');
        $r = $this->say('4');
        $this->assertContains('My orders (unpaid)', $r);
        $this->assertContains('p3-new.test', $r);
        $this->assertContains('Domain registration', $r);
        $this->assertContains('TZS 25,000', $r);
        $this->assertContains($dd->document_number, $r);
        $this->assertContains('Starter Plan — p3-host.test', $r);
        $this->assertContains($hd->document_number, $r);
        $this->assertContains('ago', $r);
        $this->assertContains('0) Back', $r);
    }

    public function test_a4_sw_wording_and_empty(): void
    {
        $c = $this->makeClient();
        $this->startSession($c);
        $this->session()->update(['language' => 'sw']);
        $this->say('10');
        $r = $this->say('4');
        $this->assertContains('Huna oda yoyote isiyolipwa', $r);
        $this->assertContains('Chagua huduma', $r);
        $this->pendingDomainOrder($c, 'p3-sw.test');
        $this->say('10');
        $r = $this->say('4');
        $this->assertContains('Oda zangu (zisizolipwa)', $r);
        $this->assertContains('zilizopita', $r);
        $r = $this->say('1');
        $this->assertContains('1) Lipa sasa', $r);
        $this->assertContains('2) Futa oda hii', $r);
    }

    public function test_a4_pick_and_pay_now_goes_to_payment_options(): void
    {
        $c = $this->makeClient();
        $this->startSession($c);
        [$doc] = $this->pendingDomainOrder($c);
        $this->say('10');
        $this->say('4');
        $card = $this->say('1');
        $this->assertContains('1) Pay now', $card);
        $this->assertContains('2) Delete this order', $card);
        $r = $this->say('1');
        $this->assertContains("Invoice {$doc->document_number}", $r);
        $this->assertContains('Pay online', $r);
        $this->assertSame('pay_invoice', $this->session()->flow);
    }

    public function test_a4_delete_confirm_cancels_invoice_and_pending_domain(): void
    {
        $c = $this->makeClient();
        $this->startSession($c);
        [$doc, $dom] = $this->pendingDomainOrder($c);
        $this->say('10');
        $this->say('4');
        $this->say('1');
        $r = $this->say('2');
        $this->assertContains('Delete the order for', $r);
        $this->assertContains('1) Yes', $r);
        $this->assertContains("Sorry, reply 1 or 2", $this->say("maybe"));
        $r = $this->say('1');
        $this->assertContains('was deleted', $r);
        $this->assertContains('Choose a service', $r);
        $this->assertSame('cancelled', $doc->fresh()->status);
        $this->assertSame('cancelled', $dom->fresh()->status);
    }

    public function test_a4_delete_declined_keeps_order(): void
    {
        $c = $this->makeClient();
        $this->startSession($c);
        [$doc, $dom] = $this->pendingDomainOrder($c);
        $this->say('10');
        $this->say('4');
        $this->say('1');
        $this->say('2');
        $r = $this->say('2');
        $this->assertContains('Awaiting payment', $r);
        $this->assertSame('sent', $doc->fresh()->status);
        $this->assertSame('pending', $dom->fresh()->status);
    }

    public function test_a4_hosting_delete_cancels_subscription(): void
    {
        $c = $this->makeClient();
        $this->startSession($c);
        [$doc, $sub] = $this->pendingHostingOrder($c);
        $this->say('10');
        $this->say('4');
        $this->say('1');
        $this->say('2');
        $this->say('yes');
        $this->assertSame('cancelled', $doc->fresh()->status);
        $this->assertSame('cancelled', $sub->fresh()->status);
    }

    public function test_a4_paid_and_partly_paid_items_are_never_touched(): void
    {
        $c = $this->makeClient();
        $this->startSession($c);
        [$paid, $pd] = $this->pendingDomainOrder($c, 'p3-paid.test');
        $paid->update(['status' => 'paid', 'paid_amount' => 25000]);
        [$part, $pt] = $this->pendingDomainOrder($c, 'p3-part.test', 40000);
        $part->update(['status' => 'partial', 'paid_amount' => 10000]);
        $this->say('10');
        $r = $this->say('4');
        $this->assertNotContains('p3-paid.test', $r);
        $this->assertContains('p3-part.test', $r);
        $card = $this->say('1');
        $this->assertContains('1) Pay now', $card);
        $this->assertNotContains('Delete this order', $card);
        $r = $this->say('2');
        $this->assertContains('Sorry, reply 1 or 0', $r);
        $this->assertSame('partial', $part->fresh()->status);
        $this->assertSame('pending', $pt->fresh()->status);
        $this->assertSame('paid', $paid->fresh()->status);
    }

    public function test_a4_order_paid_between_list_and_delete_is_not_cancelled(): void
    {
        $c = $this->makeClient();
        $this->startSession($c);
        [$doc, $dom] = $this->pendingDomainOrder($c);
        $this->say('10');
        $this->say('4');
        $this->say('1');
        $this->say('2');
        $doc->update(['status' => 'paid', 'paid_amount' => 25000]); // paid while the confirmation was open
        $r = $this->say('1');
        $this->assertContains('already paid or cancelled', $r);
        $this->assertSame('paid', $doc->fresh()->status);
        $this->assertSame('pending', $dom->fresh()->status);
    }

    public function test_a4_other_client_orders_are_isolated(): void
    {
        $mine = $this->makeClient('Asha Test');
        $other = $this->makeClient('Baraka Other', '255700000009');
        $this->startSession($mine);
        [$odoc, $odom] = $this->pendingDomainOrder($other, 'p3-theirs.test');
        $this->pendingDomainOrder($mine, 'p3-mine.test');
        $this->say('10');
        $r = $this->say('4');
        $this->assertContains('p3-mine.test', $r);
        $this->assertNotContains('p3-theirs.test', $r);
        $this->assertNotContains($odoc->document_number, $r);
        // a crafted state pointing at the other client's invoice shows nothing
        $this->session()->update(['flow' => 'my_orders', 'state' => ['step' => 'card', 'doc_id' => $odoc->id, 'can_delete' => true]]);
        $r = $this->say('2');
        $this->assertContains('already paid or cancelled', $r);
        $this->assertSame('sent', $odoc->fresh()->status);
        $this->assertSame('pending', $odom->fresh()->status);
    }

    public function test_a4_cap_of_nine_with_notice_and_back(): void
    {
        $c = $this->makeClient();
        $this->startSession($c);
        for ($i = 1; $i <= 11; $i++) $this->pendingDomainOrder($c, "p3-cap$i.test", 1000 + $i);
        $this->say('10');
        $r = $this->say('4');
        $this->assertContains('9) ', $r);
        $this->assertTrue(!str_contains($r, '10) '), 'no tenth row');
        $this->assertContains('There are 2 more', $r);
        $this->assertContains('/portal/invoices', $r);
        $this->assertContains('Sorry, reply 1-9 or 0', $this->say('12'));
        $this->assertContains('More services', $this->say('0'));
    }
}
