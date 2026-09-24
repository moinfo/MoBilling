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
        config(['services.mosms.inbound_webhook_secret' => 'test-secret', 'services.mosms.inbound_rate_limit' => 100000]);
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

    // ═══ M2: abandoned orders command ═══
    private function age(Document $d, int $days): void { DB::table('documents')->where('id', $d->id)->update(['created_at' => now()->subDays($days)]); }

    public function test_m2_expire_abandoned_orders_command(): void
    {
        $c = $this->makeClient();
        $coupon = $this->coupon(['max_uses' => 3]);
        $old = $this->makeInvoice($c, 27000, 'sent', 'Plan (WhatsApp order): old.co.tz (promo X)');
        CouponService::class; app(CouponService::class)->redeem($coupon, $c->id, $old->id, 3000.0);
        $sub = \App\Models\ClientSubscription::create(['tenant_id' => $this->tenant->id, 'client_id' => $c->id, 'product_service_id' => $this->product()->id, 'label' => 'old.co.tz', 'quantity' => 1, 'start_date' => now(), 'expire_date' => now()->addYear(), 'status' => 'pending']);
        \App\Models\RecurringInvoiceLog::create(['tenant_id' => $this->tenant->id, 'client_id' => $c->id, 'client_subscription_id' => $sub->id, 'product_service_id' => $sub->product_service_id, 'document_id' => $old->id, 'next_bill_date' => now()->toDateString()]);
        $dom = \App\Models\Domain::withoutGlobalScopes()->create(['tenant_id' => $this->tenant->id, 'client_id' => $c->id, 'name' => 'abandoned-p2.co.tz', 'status' => 'pending', 'registrar' => 'fred', 'meta' => ['order_document_id' => $old->id, 'pending_action' => 'register']]);
        $fresh = $this->makeInvoice($c, 1000, 'sent', 'Domain registered (WhatsApp order): fresh.co.tz');
        $paid = $this->makeInvoice($c, 1000, 'paid', 'Domain registered (WhatsApp order): paid.co.tz');
        $unmarked = $this->makeInvoice($c, 1000, 'sent', 'Manual staff invoice');
        $part = $this->makeInvoice($c, 5000, 'partial', 'Domain registered (WhatsApp order): part.co.tz');
        foreach ([$old, $paid, $unmarked, $part] as $d) $this->age($d, 30);
        $this->age($fresh, 2);

        \Illuminate\Support\Facades\Artisan::call('whatsapp:expire-abandoned-orders', ['--days' => 14, '--dry-run' => true]);
        $this->assertContains('would cancel', strtolower(\Illuminate\Support\Facades\Artisan::output()));
        $this->assertSame('sent', $old->fresh()->status, 'dry-run changes nothing');
        $this->assertSame(1, (int) $coupon->fresh()->uses);

        \Illuminate\Support\Facades\Artisan::call('whatsapp:expire-abandoned-orders', ['--days' => 14]);
        $this->assertSame('cancelled', $old->fresh()->status);
        $this->assertSame(0, (int) $coupon->fresh()->uses, 'coupon released');
        $this->assertSame('cancelled', $sub->fresh()->status, 'pending subscription cancelled');
        $this->assertSame('cancelled', $dom->fresh()->status, 'pending domain cancelled');
        $this->assertSame('sent', $fresh->fresh()->status, 'recent order untouched');
        $this->assertSame('paid', $paid->fresh()->status, 'paid untouched');
        $this->assertSame('sent', $unmarked->fresh()->status, 'unmarked untouched');
        $this->assertSame('partial', $part->fresh()->status, 'partial untouched');
        \Illuminate\Support\Facades\Artisan::call('whatsapp:expire-abandoned-orders', ['--days' => 14]); // idempotent
        $this->assertSame(0, (int) $coupon->fresh()->uses);
    }

    // ═══ H4: verification lockout ═══
    public function test_h4_verify_guard_thresholds_reset_and_persistence(): void
    {
        $g = app(\App\Services\WhatsappVerifyGuard::class);
        $t = $this->tenant->id;
        $k = '255711111111';
        $this->assertSame(null, $g->isLocked($t, $k));
        for ($i = 1; $i <= 4; $i++) {
            $r = $g->recordFailure($t, $k);
            $this->assertTrue(!$r['newly_locked'], "failure $i not locked");
        }
        $this->assertSame(null, $g->isLocked($t, $k));
        $r = $g->recordFailure($t, $k);
        $this->assertTrue($r['newly_locked'], '5th failure locks');
        $mins = now()->diffInMinutes($g->isLocked($t, $k), false);
        $this->assertTrue($mins >= 58 && $mins <= 60, "lock ~1h, got $mins");
        $this->assertTrue($g->claimStaffAlert($t, $k), 'staff alert claimed once');
        $this->assertTrue(!$g->claimStaffAlert($t, $k), 'not twice for the same lock');
        // survives session deletion: nothing in the session row
        WhatsappRenewalSession::withoutGlobalScopes()->where('tenant_id', $t)->delete();
        $this->assertTrue($g->isLocked($t, $k) !== null, 'lock independent of session');
        // escalation to 24h at 10
        for ($i = 6; $i <= 10; $i++) $g->recordFailure($t, $k);
        $mins = now()->diffInMinutes($g->isLocked($t, $k), false);
        $this->assertTrue($mins > 1400, "10 failures lock 24h, got $mins");
        // success resets
        $g->reset($t, $k);
        $this->assertSame(null, $g->isLocked($t, $k));
        $this->assertSame(1, $g->recordFailure($t, $k)['failures'], 'counter restarted');
        // window: old failures do not count
        DB::table('whatsapp_verify_attempts')->where('tenant_id', $t)->where('phone', $k)->update(['failures' => 4, 'last_failed_at' => now()->subHours(25)]);
        $this->assertTrue(!$g->recordFailure($t, $k)['newly_locked'], 'failures older than 24h forgotten');
        // staff policy: 5 -> 30 min
        $sk = \App\Services\WhatsappVerifyGuard::staffKey('u1');
        for ($i = 1; $i <= 5; $i++) $r = $g->recordFailure($t, $sk, \App\Services\WhatsappVerifyGuard::STAFF);
        $mins = now()->diffInMinutes($g->isLocked($t, $sk), false);
        $this->assertTrue($r['newly_locked'] && $mins >= 28 && $mins <= 30, "staff lock 30m, got $mins");
    }

    public function test_h4_surname_stop_words_and_short_tokens(): void
    {
        $m = fn ($last, $full, $typed) => \App\Services\WhatsappVerifyGuard::surnameMatches($last, $full, $typed);
        $this->assertTrue($m('Mushi', 'Asha Mushi', 'mushi'), 'person surname');
        $this->assertTrue($m(null, 'Asha Juma Mushi', 'Juma'), 'any name word');
        $this->assertTrue(!$m(null, 'Acme Trading Ltd', 'ltd'), 'ltd rejected');
        $this->assertTrue(!$m(null, 'Acme Trading Ltd', 'Trading'), 'trading rejected');
        $this->assertTrue(!$m(null, 'Acme Investments Company Limited', 'company'), 'company rejected');
        $this->assertTrue($m(null, 'Acme Trading Ltd', 'Acme'), 'distinctive token matches');
        $this->assertTrue(!$m(null, 'Al Co', 'co'), 'short/stop rejected');
        $this->assertTrue(!$m(null, 'Jo Ng Bee', 'ng'), 'token <3 rejected');
        $this->assertTrue($m('Li', 'Wei Li', 'li'), 'exact registered short last name still matches');
        $this->assertTrue(!$m('Ltd', 'X Ltd', 'ltd'), 'stop-word last name never matches');
        $this->assertTrue(!$m('Mushi', 'Asha Mushi', ''), 'empty');
    }

    // ═══ M4: reminder targets ═══
    public function test_m4_reminder_targets_model_and_command_do_not_touch_session(): void
    {
        $c = $this->makeClient();
        $d1 = \App\Models\Domain::withoutGlobalScopes()->create(['tenant_id' => $this->tenant->id, 'client_id' => $c->id, 'name' => 'one-p2.co.tz', 'status' => 'active', 'registrar' => 'fred', 'expires_at' => now()->addDays(5)]);
        $d2 = \App\Models\Domain::withoutGlobalScopes()->create(['tenant_id' => $this->tenant->id, 'client_id' => $c->id, 'name' => 'two-p2.co.tz', 'status' => 'active', 'registrar' => 'fred', 'expires_at' => now()->addDays(6)]);
        $T = \App\Models\WhatsappReminderTarget::class;
        $T::record($this->tenant->id, $this->phone, $c->id, $d1->id);
        $T::record($this->tenant->id, $this->phone, $c->id, $d2->id);
        $T::record($this->tenant->id, $this->phone, $c->id, $d2->id); // refresh, no duplicate row
        $this->assertSame(2, $T::openFor($this->tenant->id, $this->phone)->count());
        DB::table('whatsapp_reminder_targets')->where('domain_id', $d1->id)->update(['expires_at' => now()->subMinute()]);
        $this->assertSame(1, $T::openFor($this->tenant->id, $this->phone)->count(), 'expired target ignored');
    }

    // ═══ H5: cleanup command ═══
    public function test_h5_cleanup_sessions_command(): void
    {
        $c = $this->makeClient();
        $mk = fn (string $phone, array $extra) => WhatsappRenewalSession::withoutGlobalScopes()->create(array_merge(['tenant_id' => $this->tenant->id, 'phone' => $phone, 'client_id' => $c->id, 'language' => 'en', 'confirmed_at' => now(), 'expires_at' => now()->addDays(30)], $extra));
        $live = $mk('255700000101', []);
        $recentExpired = $mk('255700000102', ['expires_at' => now()->subDays(2)]);
        $oldExpired = $mk('255700000103', ['expires_at' => now()->subDays(9)]);
        $epp = $mk('255700000104', ['flow' => 'order_domain', 'state' => ['step' => 'transfer_domain_confirm', 'domain' => 'x.com', 'auth_info' => 'SECRET-EPP']]);
        $eppFresh = $mk('255700000105', ['flow' => 'order_domain', 'state' => ['step' => 'transfer_domain_confirm', 'auth_info' => 'FRESH-EPP']]);
        DB::table('whatsapp_renewal_sessions')->where('id', $epp->id)->update(['updated_at' => now()->subHours(2)]);
        WhatsappRenewalSession::withoutGlobalScopes()->whereKey($eppFresh->id)->first();

        \Illuminate\Support\Facades\Artisan::call('whatsapp:cleanup-sessions', ['--dry-run' => true]);
        $this->assertTrue(WhatsappRenewalSession::withoutGlobalScopes()->whereKey($oldExpired->id)->exists(), 'dry-run deletes nothing');
        $this->assertContains('SECRET-EPP', json_encode(WhatsappRenewalSession::withoutGlobalScopes()->find($epp->id)->state));

        \Illuminate\Support\Facades\Artisan::call('whatsapp:cleanup-sessions');
        $this->assertTrue(!WhatsappRenewalSession::withoutGlobalScopes()->whereKey($oldExpired->id)->exists(), 'long-expired purged');
        $this->assertTrue(WhatsappRenewalSession::withoutGlobalScopes()->whereKey($recentExpired->id)->exists(), 'recently expired kept (timeout notice)');
        $this->assertTrue(WhatsappRenewalSession::withoutGlobalScopes()->whereKey($live->id)->exists(), 'live kept');
        $state = WhatsappRenewalSession::withoutGlobalScopes()->find($epp->id)->state;
        $this->assertTrue(!array_key_exists('auth_info', $state) && ($state['domain'] ?? null) === 'x.com', 'stale EPP removed, rest of state kept');
        $this->assertContains('FRESH-EPP', json_encode(WhatsappRenewalSession::withoutGlobalScopes()->find($eppFresh->id)->state));
    }

    // ═══ H6: domain notifications reach WhatsApp-only clients ═══
    public function test_h6_domain_notifications_whatsapp_channel_gating_and_neutral_text(): void
    {
        $c = $this->makeClient('Wa Only', '255700000201');
        $d = \App\Models\Domain::withoutGlobalScopes()->create(['tenant_id' => $this->tenant->id, 'client_id' => $c->id, 'name' => 'wa-only-p2.com', 'status' => 'active', 'registrar' => 'namecom', 'expires_at' => now()->addYear(), 'meta' => ['namecom' => ['account_id' => 1]]]);
        $wa = \App\Channels\WhatsAppChannel::class;
        foreach ([\App\Notifications\DomainRegisteredNotification::class, \App\Notifications\DomainRenewedNotification::class, \App\Notifications\DomainReadyNotification::class] as $cls) {
            $n = new $cls($d);
            $this->tenant->forceFill(['whatsapp_enabled' => true])->save();
            $this->assertTrue(in_array($wa, $n->via($c), true), "$cls includes WhatsApp when enabled + phone");
            $this->assertTrue(in_array('mail', $n->via($c), true), 'mail leg unchanged');
            $noPhone = new Client(['name' => 'No Phone', 'phone' => null]);
            $this->assertTrue(!in_array($wa, $n->via($noPhone), true), 'no phone -> no WhatsApp');
            $this->tenant->forceFill(['whatsapp_enabled' => false])->save();
            $n = new $cls($d->fresh());
            $this->assertTrue(!in_array($wa, $n->via($c), true), 'tenant whatsapp_enabled off -> no WhatsApp');
            $text = $n->toWhatsApp($c);
            $this->assertTrue(is_string($text), 'plain text, no invented template');
            $this->assertContains('wa-only-p2.com', $text);
            $this->assertContains('Habari', $text);
            $this->assertContains('Hello', $text);
            foreach (['name.com', 'namecom', 'linode', 'usd', '$', 'registrar'] as $bad) $this->assertNotContains($bad, strtolower($text));
        }
    }

    public function test_h4_controller_locks_phone_after_five_wrong_surnames_and_resets_on_success(): void
    {
        $c = $this->makeClient('Asha Mushi');
        $c->update(['last_name' => 'Mushi']);
        // 4 wrong, then a right one resets the counter
        for ($i = 0; $i < 4; $i++) { $this->startVerify($c); $this->say('wrong' . $i); }
        $this->startVerify($c);
        $this->assertContains('Choose a service', $this->say('Mushi'));
        // 5 wrong in a row -> lock, even with the session recreated between attempts
        for ($i = 0; $i < 5; $i++) { $this->startVerify($c); $out = $this->say('nope' . $i); }
        $this->assertContains('paused attempts', $out);
        $this->startVerify($c);
        $out = $this->say('Mushi'); // correct, but locked
        $this->assertContains('paused attempts', $out);
        $this->assertTrue($this->session()?->confirmed_at === null, 'not verified while locked');
        // company stop-word cannot verify
        DB::table('whatsapp_verify_attempts')->where('tenant_id', $this->tenant->id)->delete();
        $co = $this->makeClient('Acme Trading Ltd', '255700000301');
        $this->startVerify($co);
        $out = $this->say('Ltd');
        $this->assertNotContains('Choose a service', $out);
    }

    public function test_m4_single_target_bare_one_renews_and_multiple_ask_which_domain(): void
    {
        $c = $this->makeClient();
        $T = \App\Models\WhatsappReminderTarget::class;
        $mk = fn ($n, $d) => \App\Models\Domain::withoutGlobalScopes()->create(['tenant_id' => $this->tenant->id, 'client_id' => $c->id, 'name' => $n, 'status' => 'active', 'registrar' => 'fred', 'expires_at' => now()->addDays($d), 'meta' => ['unmanaged' => true]]);
        $a = $mk('m4-a.co.tz', 5);
        $b = $mk('m4-b.co.tz', 9);
        $this->fakeBundler($c);

        // single target, no session at all
        $T::record($this->tenant->id, $this->phone, $c->id, $a->id);
        $t = $this->hit('renewal-reply', '1');
        $this->assertSame(['m4-a.co.tz'], FakeBundler::$asked);
        $this->assertSame('pay_invoice', $this->session()?->flow);
        $this->assertSame(0, $T::openFor($this->tenant->id, $this->phone)->count(), 'target consumed');

        // two targets -> "Domain gani?"
        WhatsappRenewalSession::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->delete();
        FakeBundler::$asked = [];
        $T::record($this->tenant->id, $this->phone, $c->id, $a->id);
        $T::record($this->tenant->id, $this->phone, $c->id, $b->id);
        $t = $this->hit('renewal-reply', '1');
        $this->assertSame([], FakeBundler::$asked, 'nothing billed before the choice');
        $this->assertContains('Domain gani', $t);
        $this->assertContains('1) m4-a.co.tz', $t);
        $this->assertContains('2) m4-b.co.tz', $t);
        $this->assertSame('renew_pick', $this->session()?->flow);
        $this->say('9'); // invalid
        $this->assertSame([], FakeBundler::$asked);
        $this->say('2');
        $this->assertSame(['m4-b.co.tz'], FakeBundler::$asked);
        $this->assertSame(1, $T::openFor($this->tenant->id, $this->phone)->count(), 'other domain stays open');
    }

    public function test_m4_live_flow_session_makes_bare_one_a_menu_digit_and_reminder_command_leaves_session_alone(): void
    {
        $c = $this->makeClient();
        $d = \App\Models\Domain::withoutGlobalScopes()->create(['tenant_id' => $this->tenant->id, 'client_id' => $c->id, 'name' => 'm4-cmd.co.tz', 'status' => 'active', 'registrar' => 'fred', 'expires_at' => now()->addDays(5), 'auto_renew' => false, 'meta' => ['unmanaged' => true]]);
        $this->tenant->forceFill(['whatsapp_enabled' => true, 'reminder_whatsapp_enabled' => true])->save();
        $this->startSession($c);
        $this->session()->update(['flow' => 'whois', 'state' => ['step' => 'ask_name'], 'items' => null]);
        \Illuminate\Support\Facades\Artisan::call('domains:send-expiry-reminders');
        $s = $this->session();
        $this->assertSame('whois', $s->flow, 'reminder cron did not touch the live session');
        $this->assertSame(null, $s->items);
        $this->assertTrue(\App\Models\WhatsappReminderTarget::openFor($this->tenant->id, $this->phone)->count() >= 1, 'target recorded');
        $this->fakeBundler($c);
        $this->hit('renewal-reply', '1'); // mid-flow: a digit for the flow, not a renewal
        $this->assertSame([], FakeBundler::$asked);
    }

    // ═══ M8: WhatsApp payment guards ═══
    private function payState(Client $c, Document $d, string $step = 'choose_method'): void
    {
        $this->startSession($c);
        $this->session()->update(['flow' => 'pay_invoice', 'state' => $step === 'choose_method' ? ['step' => 'choose_method', 'document_id' => $d->id] : ['step' => 'pick_invoice', 'doc_ids' => [$d->id]], 'flow_expires_at' => null]);
    }

    public function test_m8_wa_paid_or_cancelled_invoice_gets_no_link_and_no_details(): void
    {
        $this->tenant->forceFill(['pesapal_enabled' => true, 'pesapal_consumer_key' => 'k', 'pesapal_consumer_secret' => 's'])->save();
        $c = $this->makeClient();
        foreach (['paid', 'cancelled'] as $st) {
            $d = $this->makeInvoice($c, 30000, 'sent');
            // pick_invoice path (list was shown while it was still open)
            $this->payState($c, $d, 'pick_invoice');
            $d->update(['status' => $st]);
            $this->fk([]);
            $t = $this->say('1');
            $this->assertContains('already paid or cancelled', $t);
            $this->assertSame(0, Http::recorded()->count(), "$st: no Pesapal call (pick)");
            // choose_method path
            $d->update(['status' => 'sent']);
            $this->payState($c, $d);
            $d->update(['status' => $st]);
            $t = $this->say('1');
            $this->assertContains('already paid or cancelled', $t);
            $this->assertTrue(!str_contains($t, 'Pay Now'), 'no pay button');
            $this->payState($c, $d);
            $t = $this->say('2');
            $this->assertContains('already paid or cancelled', $t);
            $this->assertSame(0, Http::recorded()->count());
        }
        // Swahili wording
        $d = $this->makeInvoice($c, 1000, 'cancelled');
        $this->startSession($c);
        $this->session()->update(['language' => 'sw']);
        $this->payState($c, $d);
        $this->session()->update(['language' => 'sw']);
        $this->assertContains('tayari imelipwa/imefutwa', $this->say('1'));
    }

    public function test_m8_wa_pending_link_is_reused_within_30_minutes_and_not_duplicated(): void
    {
        $this->tenant->forceFill(['pesapal_enabled' => true, 'pesapal_consumer_key' => 'k', 'pesapal_consumer_secret' => 's'])->save();
        $c = $this->makeClient();
        $d = $this->makeInvoice($c, 30000);
        $this->fk([
            '*RequestToken*' => Http::response(['token' => 'tok']),
            '*SubmitOrderRequest*' => Http::response(['order_tracking_id' => 'TR-new1', 'redirect_url' => 'https://pay.example.test/new1']),
        ]);
        $this->payState($c, $d);
        $this->say('1');
        $submits = fn () => Http::recorded(fn ($r) => str_contains($r->url(), 'SubmitOrderRequest'))->count();
        $this->assertSame(1, $submits(), 'first pay creates one link');
        $this->payState($c, $d);
        $this->say('1');
        $this->payState($c, $d);
        $t = $this->say('1');
        $this->assertSame(1, $submits(), 'repeat taps reuse the open link');
        $this->assertSame(1, PesapalInvoicePayment::where('document_id', $d->id)->count());
        $cta = collect(Fw::$sent)->where('type', 'cta')->pluck('url')->unique()->values()->all();
        $this->assertSame(['https://pay.example.test/new1'], $cta, 'same URL every time');
        // an old link is not reused
        DB::table('pesapal_invoice_payments')->where('document_id', $d->id)->update(['created_at' => now()->subMinutes(45)]);
        $this->fk([
            '*RequestToken*' => Http::response(['token' => 'tok']),
            '*SubmitOrderRequest*' => Http::response(['order_tracking_id' => 'TR-new2', 'redirect_url' => 'https://pay.example.test/new2']),
        ]);
        $this->payState($c, $d);
        $this->say('1');
        $this->assertSame(2, PesapalInvoicePayment::where('document_id', $d->id)->count());
    }

    // ═══ M1: pending duplicate order ═══
    private function fredTld(): void
    {
        \App\Models\DomainTld::whereNull('tenant_id')->update(['is_active' => false]);
        \App\Models\DomainTld::where('tenant_id', $this->tenant->id)->delete();
        \App\Models\DomainTld::create(['tenant_id' => $this->tenant->id, 'tld' => 'co.tz', 'registrar' => 'fred', 'register_price' => 19999, 'renew_price' => 21000, 'transfer_price' => 0, 'is_active' => true, 'is_unmanaged' => false, 'is_popular' => true, 'sort_order' => 1]);
    }

    private function pendingDomainOrder(Client $c, string $name, string $invStatus = 'sent'): array
    {
        $inv = $this->makeInvoice($c, 19999, $invStatus, "Domain registration (WhatsApp order): $name (1 year)");
        $d = \App\Models\Domain::withoutGlobalScopes()->create(['tenant_id' => $this->tenant->id, 'client_id' => $c->id, 'name' => $name, 'status' => 'pending', 'registrar' => 'fred', 'auto_renew' => false, 'meta' => ['pending_action' => 'register', 'pending_years' => 1, 'order_document_id' => $inv->id, 'whatsapp_order' => true]]);
        return [$d, $inv];
    }

    private function orderAskName(Client $c): void
    {
        $this->startSession($c);
        $this->session()->update(['flow' => 'order_domain', 'state' => ['step' => 'ask_name'], 'flow_expires_at' => null]);
    }

    public function test_m1_pending_domain_order_offers_pay_or_delete_instead_of_already_registered(): void
    {
        $this->fredTld();
        FakeRegistrar::$fred = [];
        app()->instance(\App\Services\Registrar\DomainRegistrarManager::class, new FakeRegistrar());
        $c = $this->makeClient();
        [$d, $inv] = $this->pendingDomainOrder($c, 'dup-p2.co.tz');
        $coupon = $this->coupon(['max_uses' => 2]);
        app(CouponService::class)->redeem($coupon, $c->id, $inv->id, 100.0);

        $this->orderAskName($c);
        $t = $this->say('dup-p2.co.tz');
        $this->assertContains('You already ordered', $t);
        $this->assertContains($inv->document_number, $t);
        $this->assertContains('1) Pay now', $t);
        $this->assertContains('2) Delete that order', $t);
        $this->assertNotContains('already registered', $t);
        $this->assertSame('pending_dup', $this->session()?->flow);

        // 1) pay now -> the normal payment-method offer
        $t = $this->say('1');
        $this->assertContains('Choose how to pay', $t);
        $this->assertSame('pay_invoice', $this->session()?->flow);

        // 2) delete -> invoice + pending domain cancelled, coupon released
        $this->orderAskName($c);
        $this->say('dup-p2.co.tz');
        $t = $this->say('2');
        $this->assertContains('deleted', $t);
        $this->assertSame('cancelled', $inv->fresh()->status);
        $this->assertSame('cancelled', $d->fresh()->status);
        $this->assertSame(0, (int) $coupon->fresh()->uses, 'coupon released');
        // 0) back works too
        [$d2, $inv2] = $this->pendingDomainOrder($c, 'dup2-p2.co.tz');
        $this->orderAskName($c);
        $this->say('dup2-p2.co.tz');
        $this->say('0');
        $this->assertSame('sent', $inv2->fresh()->status, 'Back changes nothing');
        $this->assertSame(null, $this->session()->flow);
    }

    public function test_m1_paid_items_are_never_touched_and_keep_the_normal_message(): void
    {
        $this->fredTld();
        FakeRegistrar::$fred = [];
        app()->instance(\App\Services\Registrar\DomainRegistrarManager::class, new FakeRegistrar());
        $c = $this->makeClient();
        [$d, $inv] = $this->pendingDomainOrder($c, 'paid-p2.co.tz', 'paid');
        $this->orderAskName($c);
        $t = $this->say('paid-p2.co.tz');
        $this->assertNotContains('You already ordered', $t);
        $this->assertContains('already registered', $t);
        // a stale pending_dup on an invoice paid meanwhile: no cancel
        $inv2 = $this->makeInvoice($c, 1000, 'sent', 'x (WhatsApp order)');
        $this->startSession($c);
        $this->session()->update(['flow' => 'pending_dup', 'state' => ['step' => 'choose', 'document_id' => $inv2->id, 'name' => 'z.co.tz'], 'flow_expires_at' => null]);
        $inv2->update(['status' => 'paid']);
        $t = $this->say('2');
        $this->assertContains('already paid or cancelled', $t);
        $this->assertSame('paid', $inv2->fresh()->status);
    }

    public function test_m1_pending_hosting_order_same_plan_and_domain_offers_pay_or_delete(): void
    {
        $c = $this->makeClient();
        $plan = ProductService::create(['tenant_id' => $this->tenant->id, 'type' => 'service', 'name' => 'P2 Host', 'price' => 30000, 'tax_percent' => 0, 'unit' => 'pcs', 'category' => 'Web Hosting', 'billing_cycle' => 'yearly', 'provisioning_type' => 'whm_cpanel', 'portal_visible' => true, 'is_active' => true]);
        $inv = $this->makeInvoice($c, 30000, 'sent', 'P2 Host (WhatsApp order): host-p2.co.tz');
        $sub = \App\Models\ClientSubscription::create(['tenant_id' => $this->tenant->id, 'client_id' => $c->id, 'product_service_id' => $plan->id, 'label' => 'host-p2.co.tz', 'quantity' => 1, 'start_date' => now(), 'expire_date' => now()->addYear(), 'status' => 'pending']);
        \App\Models\RecurringInvoiceLog::create(['tenant_id' => $this->tenant->id, 'client_id' => $c->id, 'client_subscription_id' => $sub->id, 'product_service_id' => $plan->id, 'document_id' => $inv->id, 'next_bill_date' => now()->toDateString()]);
        $this->startSession($c);
        $this->session()->update(['flow' => 'order_hosting', 'state' => ['step' => 'ask_domain', 'product_service_id' => $plan->id, 'category' => 'Web Hosting'], 'flow_expires_at' => null]);
        $t = $this->say('host-p2.co.tz');
        $this->assertContains('You already ordered', $t);
        $this->say('2');
        $this->assertSame('cancelled', $inv->fresh()->status);
        $this->assertSame('cancelled', $sub->fresh()->status, 'pending subscription cancelled');
    }

    // ═══ M5: staff-assist attribution + nameserver block ═══
    public function test_m5_assisted_nameserver_change_is_refused_in_menu_and_at_confirm(): void
    {
        $c = $this->makeClient();
        $d = \App\Models\Domain::withoutGlobalScopes()->create(['tenant_id' => $this->tenant->id, 'client_id' => $c->id, 'name' => 'ns-p2.co.tz', 'status' => 'active', 'registrar' => 'fred', 'expires_at' => now()->addYear(), 'meta' => []]);
        $this->startSession($c, $this->user->id);
        $t = $this->say('8');
        $this->assertContains('nameservers is not available in staff-assist mode', $t);
        $this->assertSame(null, $this->session()->flow, 'no DNS flow started');

        $this->startSession($c, $this->user->id);
        $this->session()->update(['flow' => 'change_dns', 'state' => ['step' => 'confirm', 'domain_id' => $d->id, 'nameservers' => ['ns1.example.test', 'ns2.example.test']]]);
        $t = $this->say('1');
        $this->assertContains('not available in staff-assist mode', $t);
        $this->assertSame([], $d->fresh()->meta ?? [], 'domain untouched');
        $this->assertSame(0, \App\Models\DomainLog::where('domain_id', $d->id)->count());

        // the client's own session still reaches the DNS flow
        $this->startSession($c);
        $t = $this->say('8');
        $this->assertNotContains('staff-assist', $t);
        $this->assertSame('change_dns', $this->session()->flow);
    }

    public function test_m5_assisted_actions_are_attributed_to_the_staff_user(): void
    {
        $this->tenant->forceFill(['pesapal_enabled' => true, 'pesapal_consumer_key' => 'k', 'pesapal_consumer_secret' => 's'])->save();
        $c = $this->makeClient();
        $this->fk([
            '*RequestToken*' => Http::response(['token' => 'tok']),
            '*SubmitOrderRequest*' => Http::response(['order_tracking_id' => 'TR-m5', 'redirect_url' => 'https://pay.example.test/m5']),
        ]);
        $logged = [];
        \Illuminate\Support\Facades\Log::listen(function ($e) use (&$logged) { if ($e->message === 'WhatsApp staff-assist action') $logged[] = $e->context; });

        $inv = $this->makeInvoice($c, 20000);
        $this->payState($c, $inv);
        $this->startSession($c, $this->user->id);
        $this->session()->update(['flow' => 'pay_invoice', 'state' => ['step' => 'choose_method', 'document_id' => $inv->id]]);
        $this->say('1');
        $this->assertSame($this->user->id, $inv->fresh()->created_by, 'invoice stamped with the assisting staff user');
        $this->assertTrue(count($logged) >= 1 && ($logged[0]['assisted_by_user_id'] ?? null) === $this->user->id && ($logged[0]['action'] ?? null) === 'payment_link', 'log carries assisted_by_user_id');

        // a client's own (unassisted) session leaves no staff attribution
        $inv2 = $this->makeInvoice($c, 20000);
        $logged = [];
        $this->payState($c, $inv2);
        $this->say('2');
        $this->assertSame(null, $inv2->fresh()->created_by);
        $this->assertSame([], $logged);
    }
}

class FakeBundler extends \App\Services\Hosting\RenewalBundleService
{
    public static array $asked = [];
    public static ?Document $doc = null;
    public function generate(\App\Models\HostingAccount $h, bool $selfService = false): Document
    {
        self::$asked[] = $h->domain;
        return self::$doc;
    }
}
