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
        $this->assertNotContains('p3-paid.test — Domain registration', $r); // paid: only as a being-set-up line
        $this->assertContains('p3-paid.test — Being set up', $r);
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

    // ═══ A5: Payments & receipts ═══
    private function payIn(Client $c, Document $d, float $amt, string $method = 'mpesa', ?string $date = null): PaymentIn
    {
        $p = PaymentIn::withoutGlobalScopes()->create(['tenant_id' => $this->tenant->id, 'document_id' => $d->id, 'client_id' => $c->id, 'amount' => $amt, 'payment_date' => $date ?? now()->toDateString(), 'payment_method' => $method]);
        return $p;
    }

    private function paidInvoice(Client $c, float $total, string $date, string $method = 'mpesa'): array
    {
        $d = $this->makeInvoice($c, $total, 'paid');
        $d->update(['paid_amount' => $total, 'date' => $date]);
        return [$d, $this->payIn($c, $d, $total, $method, $date)];
    }

    public function test_a5_menu_lists_all_three_options(): void
    {
        $c = $this->makeClient();
        $this->startSession($c);
        $this->assertContains('5) Payments & receipts', $this->say('10'));
        $r = $this->say('5');
        $this->assertContains('1) My recent payments', $r);
        $this->assertContains('2) My paid invoices', $r);
        $this->assertContains('3) Statement', $r);
        $this->assertContains('Sorry, reply 1, 2, 3 or 0', $this->say('9'));
        $this->assertContains('More services', $this->say('0'));
    }

    public function test_a5_recent_payments_newest_first_max_five_then_receipt_cta(): void
    {
        $c = $this->makeClient();
        $this->startSession($c);
        $docs = [];
        for ($i = 1; $i <= 6; $i++) { [$d] = $this->paidInvoice($c, 1000 * $i, now()->subDays(10 - $i)->toDateString(), $i % 2 ? 'mpesa' : 'bank'); $docs[$i] = $d; }
        $this->say('10');
        $this->say('5');
        $r = $this->say('1');
        $this->assertContains('Recent payments', $r);
        $this->assertContains('1) ' . now()->subDays(4)->format('d M Y') . ' — ' . $docs[6]->document_number . ' — TZS 6,000 — Bank', $r);
        $this->assertContains('5) ', $r);
        $this->assertTrue(!str_contains($r, '6) '), 'max five');
        $this->assertNotContains($docs[1]->document_number, $r);
        $card = $this->say('1');
        $this->assertContains('RCT-', $card);
        $this->assertContains('1) Send me the receipt', $card);
        Fw::$sent = [];
        $r = $this->say('1');
        $cta = Fw::$sent[0];
        $this->assertSame('cta', $cta['type']);
        $this->assertContains('TZS 6,000', $cta['text']);
        $this->assertContains('/portal/payments', $cta['url']);
        $this->assertContains('Choose a service', $r); // back at the root menu
    }

    public function test_a5_paid_invoices_list_and_resend_link(): void
    {
        $c = $this->makeClient();
        $this->startSession($c);
        [$d] = $this->paidInvoice($c, 12000, now()->subDays(2)->toDateString());
        $open = $this->makeInvoice($c, 9000, 'sent');
        $this->say('10');
        $this->say('5');
        $r = $this->say('2');
        $this->assertContains('Paid invoices', $r);
        $this->assertContains($d->document_number, $r);
        $this->assertNotContains($open->document_number, $r);
        $card = $this->say('1');
        $this->assertContains('1) Send me the invoice', $card);
        Fw::$sent = [];
        $this->say('1');
        $this->assertSame('cta', Fw::$sent[0]['type']);
        $this->assertContains("/pay/{$d->id}", Fw::$sent[0]['url']);
    }

    public function test_a5_statement_totals_and_link(): void
    {
        $c = $this->makeClient();
        $this->startSession($c);
        $this->paidInvoice($c, 10000, now()->subDays(60)->toDateString());
        $this->paidInvoice($c, 5000, now()->subDays(3)->toDateString());
        $this->makeInvoice($c, 8000, 'sent')->update(['date' => now()->subDays(1)->toDateString()]);
        $this->makeInvoice($c, 7777, 'cancelled');
        $this->say('10');
        $this->say('5');
        Fw::$sent = [];
        $this->say('3');
        $cta = Fw::$sent[0];
        $this->assertSame('cta', $cta['type']);
        $this->assertContains('Total invoiced: TZS 23,000', $cta['text']);
        $this->assertContains('Total paid: TZS 15,000', $cta['text']);
        $this->assertContains('Balance due: TZS 8,000', $cta['text']);
        $this->assertContains('Invoiced: TZS 13,000', $cta['text']);
        $this->assertContains('Paid: TZS 5,000', $cta['text']);
        $this->assertContains('/portal/statement', $cta['url']);
    }

    public function test_a5_sw_and_empty_states(): void
    {
        $c = $this->makeClient();
        $this->startSession($c);
        $this->session()->update(['language' => 'sw']);
        $this->say('10');
        $r = $this->say('5');
        $this->assertContains('Malipo na risiti', $r);
        $this->assertContains('Hakuna malipo yaliyorekodiwa', $this->say('1'));
        $this->say('10'); $this->say('5');
        $this->assertContains('Huna invoice iliyolipwa', $this->say('2'));
        $this->say('10'); $this->say('5');
        Fw::$sent = [];
        $this->say('3');
        $this->assertContains('Deni linalodaiwa: TZS 0', Fw::$sent[0]['text']);
    }

    public function test_a5_other_clients_documents_never_exposed(): void
    {
        $mine = $this->makeClient('Asha Test');
        $other = $this->makeClient('Baraka Other', '255700000009');
        $this->startSession($mine);
        [$od, $op] = $this->paidInvoice($other, 99999, now()->toDateString());
        $this->paidInvoice($mine, 1500, now()->toDateString());
        $this->say('10'); $this->say('5');
        $r = $this->say('1');
        $this->assertNotContains($od->document_number, $r);
        $this->assertNotContains('99,999', $r);
        $r = $this->say('1'); $r .= $this->say('1');
        $this->assertNotContains('99,999', $r);
        // crafted state pointing at the other client's payment / invoice
        $this->say('10'); $this->say('5'); $this->say('1');
        $this->session()->update(['state' => ['step' => 'pay_card', 'payment_id' => $op->id]]);
        Fw::$sent = [];
        $r = $this->say('1');
        $this->assertContains('no longer available', $r);
        $this->assertTrue(!str_contains(json_encode(Fw::$sent), '99,999'));
        $this->say('10'); $this->say('5'); $this->say('2');
        $this->session()->update(['state' => ['step' => 'inv_card', 'document_id' => $od->id]]);
        $r = $this->say('1');
        $this->assertContains('no longer available', $r);
        $this->say('10'); $this->say('5');
        Fw::$sent = [];
        $this->say('3');
        $this->assertNotContains('99,999', Fw::$sent[0]['text']);
    }

    // ═══ B: "being set up" status lines ═══
    private function activeDomain(Client $c, string $name): \App\Models\Domain
    {
        return \App\Models\Domain::create(['tenant_id' => $this->tenant->id, 'client_id' => $c->id, 'name' => $name, 'status' => 'active', 'expires_at' => now()->addDays(100), 'meta' => ['unmanaged' => true]]);
    }

    public function test_b_paid_pending_domain_shows_being_set_up_in_my_domains(): void
    {
        $c = $this->makeClient();
        $this->startSession($c);
        $this->activeDomain($c, 'p3-live.test');
        [$doc] = $this->pendingDomainOrder($c, 'p3-wait.test');
        $doc->update(['status' => 'paid', 'paid_amount' => 25000]);
        [$unpaid] = $this->pendingDomainOrder($c, 'p3-unpaid.test');
        $r = $this->say('11');
        $this->assertContains('p3-live.test', $r);
        $this->assertContains('p3-wait.test — Being set up (payment received)', $r);
        $this->assertNotContains('p3-unpaid.test', $r);
    }

    public function test_b_only_setting_up_domain_and_swahili(): void
    {
        $c = $this->makeClient();
        $this->startSession($c);
        $this->session()->update(['language' => 'sw']);
        [$doc] = $this->pendingDomainOrder($c, 'p3-wait.test');
        $doc->update(['status' => 'paid', 'paid_amount' => 25000]);
        $r = $this->say('11');
        $this->assertContains('p3-wait.test — Inaandaliwa (malipo yamepokelewa)', $r);
        $this->assertNotContains('Huna domain', $r);
        $this->assertContains('Habari', $this->say('0'));
    }

    public function test_b_paid_hosting_subscription_without_account_shows_in_my_hosting_and_orders(): void
    {
        $c = $this->makeClient();
        $this->startSession($c);
        [$doc] = $this->pendingHostingOrder($c, 'p3-host.test');
        $doc->update(['status' => 'paid', 'paid_amount' => 60000]);
        $r = $this->say('12');
        $this->assertContains('p3-host.test — Being set up (payment received)', $r);
        $this->assertNotContains("You don't have any hosting", $r);
        $this->say('MENU');
        $this->say('10');
        $r = $this->say('4');
        $this->assertContains('You have no unpaid orders', $r);
        $this->assertContains('p3-host.test — Being set up', $r);
    }

    public function test_b_unpaid_hosting_and_other_clients_not_listed_as_setting_up(): void
    {
        $mine = $this->makeClient('Asha Test');
        $other = $this->makeClient('Baraka Other', '255700000009');
        $this->startSession($mine);
        $this->pendingHostingOrder($mine, 'p3-unpaid-host.test');
        [$od] = $this->pendingDomainOrder($other, 'p3-theirs.test');
        $od->update(['status' => 'paid', 'paid_amount' => 25000]);
        $r = $this->say('12');
        $this->assertNotContains('Being set up', $r);
        $r = $this->say('11');
        $this->assertNotContains('p3-theirs.test', $r);
    }

    // ═══ C: STOP / START ═══
    private function pushNote(bool $transactional = false): \Illuminate\Notifications\Notification
    {
        return new class($transactional) extends \Illuminate\Notifications\Notification {
            public bool $whatsappTransactional;
            public function __construct(bool $t) { $this->whatsappTransactional = $t; }
            public function toWhatsApp($n) { return 'REMINDER-BODY'; }
        };
    }

    private function pushedTexts(): array
    {
        return array_values(array_filter(Fw::$sent, fn ($m) => ($m['type'] ?? '') === 'push'));
    }

    public function test_c_stop_opts_out_replies_and_gates_the_whatsapp_channel(): void
    {
        $c = $this->makeClient();
        $this->startSession($c);
        $ch = new \App\Channels\WhatsAppChannel(new Fw3());
        $ch->send($c->fresh(), $this->pushNote());
        $this->assertSame(1, count($this->pushedTexts()), 'reminder goes out before STOP');
        $r = $this->say('stop');
        $this->assertContains('Okay, you will no longer receive WhatsApp reminders. Type START to turn them back on.', $r);
        $this->assertTrue($c->fresh()->whatsapp_opt_out_at !== null);
        Fw::$sent = [];
        $ch->send($c->fresh(), $this->pushNote());
        $this->assertSame(0, count($this->pushedTexts()), 'reminder blocked after STOP');
        $ch->send($c->fresh(), $this->pushNote(true));
        $this->assertSame(1, count($this->pushedTexts()), 'security notices still delivered');
        // transactional reply to a message the client starts is still allowed
        $r = $this->say('11');
        $this->assertTrue($r !== '', 'bot still answers the client');
    }

    public function test_c_swahili_words_and_reply_text_and_start_reenables(): void
    {
        $c = $this->makeClient();
        $this->startSession($c);
        $this->session()->update(['language' => 'sw']);
        foreach (['ACHA', ' Sitaki ', 'UNSUBSCRIBE'] as $w) {
            $c->forceFill(['whatsapp_opt_out_at' => null])->save();
            $this->assertContains('Sawa, hutapokea vikumbusho vya WhatsApp tena. Andika ANZA kuwasha tena.', $this->say($w));
            $this->assertTrue($c->fresh()->whatsapp_opt_out_at !== null, $w);
        }
        $r = $this->say('ANZA');
        $this->assertContains('vimewashwa tena', $r);
        $this->assertSame(null, $c->fresh()->whatsapp_opt_out_at);
        $ch = new \App\Channels\WhatsAppChannel(new Fw3());
        Fw::$sent = [];
        $ch->send($c->fresh(), $this->pushNote());
        $this->assertSame(1, count($this->pushedTexts()));
        $c->forceFill(['whatsapp_opt_out_at' => now()])->save();
        $this->session()->update(['language' => 'en']);
        $this->assertContains('back on', $this->say('washa'));
        $this->assertSame(null, $c->fresh()->whatsapp_opt_out_at);
        $c->fresh()->forceFill(['whatsapp_opt_out_at' => now()])->save();
        $this->assertContains('back on', $this->say('START'));
    }

    public function test_c_only_the_whole_message_counts_and_unverified_phone_works(): void
    {
        $c = $this->makeClient();
        $this->startSession($c);
        $this->say('please stop the domain order');
        $this->assertSame(null, $c->fresh()->whatsapp_opt_out_at);
        $this->say('stop it');
        $this->assertSame(null, $c->fresh()->whatsapp_opt_out_at);
        // no session at all: matched by phone
        WhatsappRenewalSession::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->delete();
        $r = $this->say('STOP');
        $this->assertContains('WhatsApp reminders', $r);
        $this->assertTrue($c->fresh()->whatsapp_opt_out_at !== null);
        // START/ANZA from a NON opted-out unknown/normal contact is not swallowed (starts the normal flow)
        $c->forceFill(['whatsapp_opt_out_at' => null])->save();
        $r = $this->say('ANZA');
        $this->assertContains('Please select your preferred language', $r);
    }

    public function test_c_stranger_stop_is_not_swallowed(): void
    {
        $r = $this->say('STOP', '255711111111');
        $this->assertContains('Please select your preferred language', $r); // unknown number: normal flow
    }

    public function test_c_client_not_a_notifiable_client_is_unaffected(): void
    {
        $ch = new \App\Channels\WhatsAppChannel(new Fw3());
        $u = new class { public $phone = '255700000001'; public $tenant; };
        $u->tenant = $this->tenant;
        Fw::$sent = [];
        $ch->send($u, $this->pushNote());
        $this->assertSame(1, count($this->pushedTexts()));
    }
}

/** Records the push-style sends (WhatsAppChannel path) next to the session replies. */
class Fw3 extends Fw
{
    public function sendText(Tenant $tenant, string $recipient, string $message): array { self::$sent[] = ['type' => 'push', 'text' => $message]; return []; }
    public function sendTemplate(Tenant $tenant, string $recipient, string $template, array $parameters = [], string $language = 'en', ?string $buttonUrlParam = null): array { self::$sent[] = ['type' => 'push', 'text' => $template]; return []; }
}
