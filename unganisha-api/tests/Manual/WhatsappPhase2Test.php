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
}
