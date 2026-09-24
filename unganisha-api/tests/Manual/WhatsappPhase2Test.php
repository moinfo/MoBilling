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
 * Phase 2 workflow hardening (M8 money guards, M2 coupons, M4 reminder targets, H6, H4, H5, M1, M5, M6).
 * Live DB inside an ALWAYS-rolled-back transaction; WhatsApp behind a recording fake; every HTTP call faked
 * with preventStrayRequests.   php tests/Manual/run_whatsapp_phase2.php [name-filter]
 */
class WhatsappPhase2Test
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
        config(['services.mosms.inbound_webhook_secret' => 'test-secret']);
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

    public function checkNeutral(): void
    {
        foreach (Fw::$sent as $m) {
            foreach (['name.com', 'namecom', 'linode', 'usd', '$'] as $bad) {
                if (str_contains(strtolower($m['text']), $bad)) $this->fail("supplier/cost leak '$bad' in reply:\n{$m['text']}");
            }
        }
    }

    // ═══ M8: IPN double-payment guard ═══
    private function pesapalPayment(Document $d, float $amount, string $ref): PesapalInvoicePayment
    {
        $this->tenant->forceFill(['pesapal_consumer_key' => 'k', 'pesapal_consumer_secret' => 's'])->save();
        return PesapalInvoicePayment::create([
            'tenant_id' => $this->tenant->id, 'document_id' => $d->id, 'merchant_reference' => "MR-$ref", 'order_tracking_id' => "TR-$ref",
            'pesapal_redirect_url' => 'https://pay.example.test/x', 'amount' => $amount, 'currency' => 'TZS', 'status' => 'pending',
        ]);
    }

    private function ipn(string $ref): int
    {
        $this->fk([
            '*RequestToken*' => Http::response(['token' => 'tok']),
            '*GetTransactionStatus*' => Http::response(['status_code' => 1, 'payment_status_description' => 'Completed', 'payment_method' => 'MPESA', 'confirmation_code' => "CC-$ref"]),
        ]);
        $req = Request::create('/api/tenant-pesapal/ipn', 'GET', ['OrderTrackingId' => "TR-$ref", 'OrderMerchantReference' => "MR-$ref"], [], [], ['HTTP_ACCEPT' => 'application/json']);
        return app()->handle($req)->getStatusCode();
    }

    private function paidSum(Document $d): float { return (float) PaymentIn::withoutGlobalScopes()->where('document_id', $d->id)->sum('amount'); }

    public function test_m8_ipn_normal_payment_books_once_and_is_idempotent(): void
    {
        $c = $this->makeClient();
        $d = $this->makeInvoice($c, 50000);
        $p = $this->pesapalPayment($d, 50000, 'a1');
        $this->assertSame(200, $this->ipn('a1'));
        $this->assertSame(200, $this->ipn('a1')); // duplicate delivery
        $this->assertSame(50000.0, $this->paidSum($d));
        $this->assertSame('paid', $d->fresh()->status);
        $this->assertSame(1, PaymentIn::withoutGlobalScopes()->where('document_id', $d->id)->count());
        $this->assertSame(0, ClientCredit::withoutGlobalScopes()->where('client_id', $c->id)->count());
    }

    public function test_m8_ipn_on_already_paid_invoice_credits_wallet_instead_of_double_booking(): void
    {
        $c = $this->makeClient();
        $d = $this->makeInvoice($c, 50000);
        PaymentIn::withoutGlobalScopes()->create(['tenant_id' => $this->tenant->id, 'document_id' => $d->id, 'client_id' => $c->id, 'amount' => 50000, 'payment_date' => now()->toDateString(), 'payment_method' => 'cash']);
        $d->update(['status' => 'paid']);
        $this->pesapalPayment($d, 50000, 'b1');
        $this->assertSame(200, $this->ipn('b1'));
        $this->assertSame(50000.0, $this->paidSum($d), 'no second PaymentIn');
        $this->assertSame(50000.0, (float) $c->fresh()->credit_balance, 'excess credited to wallet');
        $this->assertSame(200, $this->ipn('b1'));
        $this->assertSame(50000.0, (float) $c->fresh()->credit_balance, 'idempotent: credited once');
        $this->assertSame(1, ClientCredit::withoutGlobalScopes()->where('client_id', $c->id)->count());
    }

    public function test_m8_ipn_on_cancelled_invoice_credits_whole_amount(): void
    {
        $c = $this->makeClient();
        $d = $this->makeInvoice($c, 20000, 'cancelled');
        $this->pesapalPayment($d, 20000, 'c1');
        $this->ipn('c1');
        $this->assertSame(0.0, $this->paidSum($d));
        $this->assertSame(20000.0, (float) $c->fresh()->credit_balance);
        $this->assertSame('cancelled', $d->fresh()->status, 'cancelled invoice is not revived');
    }

    public function test_m8_ipn_overpayment_books_balance_and_credits_rest(): void
    {
        $c = $this->makeClient();
        $d = $this->makeInvoice($c, 50000, 'partial');
        PaymentIn::withoutGlobalScopes()->create(['tenant_id' => $this->tenant->id, 'document_id' => $d->id, 'client_id' => $c->id, 'amount' => 30000, 'payment_date' => now()->toDateString(), 'payment_method' => 'cash']);
        $this->pesapalPayment($d, 50000, 'd1'); // link was created for the full amount before the cash payment
        $this->ipn('d1');
        $this->assertSame(50000.0, $this->paidSum($d), 'invoice total, not more');
        $this->assertSame(30000.0, (float) $c->fresh()->credit_balance);
        $this->assertSame('paid', $d->fresh()->status);
    }

    public function test_m8_link_guard_payable_and_pending_reuse(): void
    {
        $g = app(\App\Services\PesapalLinkGuard::class);
        $c = $this->makeClient();
        $d = $this->makeInvoice($c, 40000);
        $this->assertTrue($g->payable($d) !== null, 'sent invoice is payable');
        foreach (['paid', 'cancelled', 'draft'] as $st) {
            $d->update(['status' => $st]);
            $this->assertSame(null, $g->payable($d), "$st is not payable");
        }
        $d->update(['status' => 'partial']);
        PaymentIn::withoutGlobalScopes()->create(['tenant_id' => $this->tenant->id, 'document_id' => $d->id, 'client_id' => $c->id, 'amount' => 40000, 'payment_date' => now()->toDateString(), 'payment_method' => 'cash']);
        $this->assertSame(null, $g->payable($d), 'zero balance is not payable');

        $d2 = $this->makeInvoice($c, 40000);
        $p = $this->pesapalPayment($d2, 40000, 'r1');
        $this->assertSame($p->id, $g->reusablePending($d2, 40000.0)?->id, 'fresh same-amount link reused');
        $this->assertSame(null, $g->reusablePending($d2, 10000.0), 'different amount not reused');
        DB::table('pesapal_invoice_payments')->where('id', $p->id)->update(['created_at' => now()->subMinutes(31)]);
        $this->assertSame(null, $g->reusablePending($d2, 40000.0), 'older than 30 min not reused');
        DB::table('pesapal_invoice_payments')->where('id', $p->id)->update(['created_at' => now(), 'status' => 'completed']);
        $this->assertSame(null, $g->reusablePending($d2, 40000.0), 'completed not reused');
    }

    public function test_m8_public_checkout_reuses_open_link_and_blocks_cancelled(): void
    {
        $c = $this->makeClient();
        $d = $this->makeInvoice($c, 40000);
        $this->tenant->forceFill(['pesapal_enabled' => true])->save();
        $p = $this->pesapalPayment($d, 40000, 'r2');
        $res = app()->handle(Request::create("/api/pay/{$d->id}/checkout", 'POST', [], [], [], ['HTTP_ACCEPT' => 'application/json']));
        $body = json_decode($res->getContent(), true);
        if ($res->getStatusCode() === 404) { $this->fail('checkout route path changed: ' . $res->getContent()); }
        $this->assertSame($p->id, $body["payment_id"] ?? null, "existing link returned: " . $res->getContent());
        $this->assertSame(0, Http::recorded()->count(), 'no Pesapal call made');
        $d->update(['status' => 'cancelled']);
        $res = app()->handle(Request::create("/api/pay/{$d->id}/checkout", 'POST', [], [], [], ['HTTP_ACCEPT' => 'application/json']));
        $this->assertSame(400, $res->getStatusCode());
    }

    // ═══ M2: coupons ═══
    private function coupon(array $o = []): Coupon
    {
        return Coupon::withoutGlobalScopes()->create(array_merge(['tenant_id' => $this->tenant->id, 'code' => 'P2' . strtoupper(substr(uniqid(), -6)), 'type' => 'percent', 'value' => 10, 'applies_to' => 'all', 'is_active' => true], $o));
    }

    private function product(): ProductService
    {
        return ProductService::create(['tenant_id' => $this->tenant->id, 'type' => 'service', 'name' => 'P2 Plan', 'price' => 30000, 'tax_percent' => 0, 'unit' => 'pcs', 'billing_cycle' => 'yearly', 'is_active' => true]);
    }

    public function test_m2_coupon_released_when_unpaid_invoice_cancelled_and_idempotent(): void
    {
        $svc = app(CouponService::class);
        $c = $this->makeClient();
        $coupon = $this->coupon(['max_uses' => 1]);
        $d = $this->makeInvoice($c, 27000, 'sent', 'Plan (WhatsApp order): a.com (promo X)');
        $this->assertTrue($svc->redeem($coupon, $c->id, $d->id, 3000.0));
        $this->assertSame(1, (int) $coupon->fresh()->uses);
        $c2 = $this->makeClient('Other Person', '255700000002');
        $d2 = $this->makeInvoice($c2, 27000);
        $this->assertTrue(!$svc->redeem($coupon->fresh(), $c2->id, $d2->id, 3000.0), 'cap reached');

        $d->update(['status' => 'cancelled']); // observer hook
        $this->assertSame(0, (int) $coupon->fresh()->uses, 'use released');
        $d->update(['status' => 'sent']);
        $d->update(['status' => 'cancelled']); // again
        $this->assertSame(0, (int) $coupon->fresh()->uses, 'no double release / no negative');
        $this->assertTrue($svc->redeem($coupon->fresh(), $c2->id, $d2->id, 3000.0), 'usable again after release');
    }

    public function test_m2_paid_invoice_never_releases_coupon(): void
    {
        $svc = app(CouponService::class);
        $c = $this->makeClient();
        $coupon = $this->coupon(['max_uses' => 5]);
        $d = $this->makeInvoice($c, 27000, 'paid');
        $svc->redeem($coupon, $c->id, $d->id, 3000.0);
        $this->assertSame(0, $svc->releaseForDocument($d));
        $this->assertSame(1, (int) $coupon->fresh()->uses);
    }

    public function test_m2_per_client_limit_enforced_in_validate_and_redeem(): void
    {
        $svc = app(CouponService::class);
        $p = $this->product();
        $a = $this->makeClient();
        $b = $this->makeClient('Bee Person', '255700000003');
        $coupon = $this->coupon(['max_uses_per_client' => 1]);
        $unl = $this->coupon(); // null = unlimited
        $this->assertSame(null, $svc->validateForOrder($coupon->code, $this->tenant->id, $p, 30000.0, $a->id)['error']);
        $d = $this->makeInvoice($a, 27000);
        $this->assertTrue($svc->redeem($coupon, $a->id, $d->id, 3000.0));
        $r = $svc->validateForOrder($coupon->code, $this->tenant->id, $p, 30000.0, $a->id);
        $this->assertTrue($r['error'] !== null, 'second use by same client rejected');
        $this->assertSame(null, $svc->validateForOrder($coupon->code, $this->tenant->id, $p, 30000.0, $b->id)['error'], 'other client unaffected');
        $this->assertTrue(!$svc->redeem($coupon->fresh(), $a->id, $this->makeInvoice($a)->id, 3000.0), 'redeem also enforces');
        for ($i = 0; $i < 3; $i++) $svc->redeem($unl, $a->id, $this->makeInvoice($a)->id, 1.0);
        $this->assertSame(null, $svc->validateForOrder($unl->code, $this->tenant->id, $p, 30000.0, $a->id)['error'], 'null = unlimited');
        // cancelling the order frees the client's use
        $d->update(['status' => 'cancelled']);
        $this->assertSame(null, $svc->validateForOrder($coupon->code, $this->tenant->id, $p, 30000.0, $a->id)['error'], 'released use is reusable');
    }
}
