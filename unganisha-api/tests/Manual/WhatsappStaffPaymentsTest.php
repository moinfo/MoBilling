<?php

namespace Tests\Manual;

use App\Models\Client;
use App\Models\Document;
use App\Models\MosmsAccount;
use App\Models\PaymentIn;
use App\Models\Tenant;
use App\Models\User;
use App\Models\WhatsappRenewalSession;
use App\Notifications\PaymentReceiptNotification;
use App\Services\WhatsAppService;
use Illuminate\Http\Client\Factory;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Notification;

/**
 * WhatsApp staff menu option 3 (record offline payment). Live DB inside an ALWAYS-rolled-back transaction;
 * WhatsApp behind a recording fake; HTTP blocked.   php tests/Manual/run_whatsapp_staff_payments.php [name-filter]
 */
class WhatsappStaffPaymentsTest
{
    private function fail(string $m): void { throw new \RuntimeException($m); }
    public function assertSame($e, $a, string $m = ''): void { if ($e !== $a) $this->fail(($m ? "$m: " : '') . 'expected ' . var_export($e, true) . ' got ' . var_export($a, true)); }
    public function assertTrue($c, string $m = 'not true'): void { if (!$c) $this->fail($m); }
    public function assertContains($n, $h): void { if (!str_contains($h, $n)) $this->fail("missing '$n' in:\n$h"); }
    public function assertNotContains($n, $h): void { if (str_contains($h, $n)) $this->fail("unexpected '$n' in:\n$h"); }

    private Tenant $tenant;
    private User $staff;
    private string $phone;
    private string $rawPhone = '255700000001';

    public function setUp(): void
    {
        $this->phone = \App\Helpers\PhoneHelper::normalize($this->rawPhone);
        DB::beginTransaction();
        config(['cache.default' => 'array']);
        $this->tenant = Tenant::withoutGlobalScopes()->where('name', 'MoBilling Test Co')->firstOrFail();
        $this->staff = User::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->firstOrFail();
        auth()->login($this->staff);
        config(['services.mosms.inbound_webhook_secret' => 'test-secret', 'services.mosms.inbound_rate_limit' => 100000, 'services.mosms.duplicate_window' => 0]);
        MosmsAccount::create(['tenant_id' => $this->tenant->id, 'mosms_tenant_id' => 987654321, 'email' => 'x@example.test', 'token' => 'x', 'sender' => 'x']);
        $this->tenant->payment_methods = [
            ['value' => 'mpesa', 'label' => 'Lipa Namba / Mobile money'], ['value' => 'bank', 'label' => 'Benki'], ['value' => 'pesapal', 'label' => 'Pesapal'],
        ];
        $this->tenant->save();
        $this->staff->forceFill(['phone' => '0' . substr($this->rawPhone, 3), 'is_active' => true, 'whatsapp_pin_hash' => Hash::make('1234'),
            'whatsapp_pin_failed_count' => 0, 'whatsapp_pin_failed_at' => null, 'whatsapp_pin_locked_until' => null])->save();
        Http::swap(new Factory()); Http::preventStrayRequests(); Http::fake([]);
        Notification::fake();
        Fw::$sent = [];
        app()->bind(WhatsAppService::class, fn () => new Fw());
    }

    public function tearDown(): void { DB::rollBack(); }

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

    private function makeClient(string $name = 'Asha Test'): Client
    {
        return Client::create(['tenant_id' => $this->tenant->id, 'name' => $name, 'phone' => '255700000777', 'email' => strtolower(str_replace(' ', '', $name)) . '@example.test', 'status' => 'active']);
    }

    private function makeInvoice(Client $c, float $total = 50000, string $status = 'sent', ?string $due = null, ?string $tenantId = null): Document
    {
        static $n = 0;
        return Document::withoutGlobalScopes()->create([
            'tenant_id' => $tenantId ?? $this->tenant->id, 'client_id' => $c->id, 'type' => 'invoice',
            'document_number' => 'SP-' . (++$n) . '-' . substr(uniqid(), -5), 'date' => '2026-01-01', 'due_date' => $due ?? '2026-02-01',
            'subtotal' => $total, 'discount_amount' => 0, 'tax_amount' => 0, 'total' => $total, 'status' => $status,
        ]);
    }

    /** STAFF -> PIN -> option 3 -> search text; returns last reply. */
    private function toMethod(Document $d, string $pick = '1'): string
    {
        $this->say('STAFF'); $this->say('1234');
        $this->assertSame('staff_menu', $this->session()?->flow);
        $this->say('3');
        $r = $this->say($d->document_number);
        $this->assertContains($d->document_number, $r);
        $this->say('1'); // pick the invoice
        return $this->say($pick); // pick the method
    }

    public function checkNeutral(): void
    {
        foreach (Fw::$sent as $m) {
            foreach (['name.com', 'namecom', 'linode', 'usd', '$'] as $bad) {
                if (str_contains(strtolower($m['text']), $bad)) $this->fail("leak '$bad' in reply:\n{$m['text']}");
            }
        }
    }

    public function test_menu_shows_option_3_and_full_payment_flow(): void
    {
        $c = $this->makeClient(); $d = $this->makeInvoice($c, 55000);
        $this->say('STAFF'); $menu = $this->say('1234');
        $this->assertContains('3) Pokea Malipo (Lipa Namba / Benki)', $menu);
        $this->assertContains('1) Followups Zangu', $menu);
        $this->assertContains('2) Tafuta Mteja Kumsaidia', $menu);
        $r = $this->say('3');
        $this->assertContains('Pokea Malipo', $r);
        $r = $this->say('LIST');
        $this->assertContains("1) {$d->document_number} — Asha Test — salio TZS 55,000 — ⚠️ imechelewa", $r);
        $r = $this->say('1');
        $this->assertContains('Jumla: TZS 55,000 | Imelipwa: TZS 0 | Salio: TZS 55,000', $r);
        $this->assertContains('1) Lipa Namba / Mobile money', $r);
        $this->assertContains('2) Benki', $r);
        $this->assertNotContains('Pesapal', $r);
        $r = $this->say('1');
        $this->assertContains('namba ya kumbukumbu', $r);
        $r = $this->say('TXN12345');
        $this->assertContains('1) Lipa salio lote (TZS 55,000)', $r);
        $r = $this->say('1');
        foreach (['Mteja: Asha Test', "Invoice: {$d->document_number}", 'Kumbukumbu: TXN12345', 'Kiasi: TZS 55,000', 'Salio jipya: TZS 0', '1) Ndiyo, rekodi'] as $x) $this->assertContains($x, $r);
        $this->assertSame(0, PaymentIn::where('document_id', $d->id)->count(), 'nothing recorded before confirm');
        $r = $this->say('1');
        $this->assertContains("Imerekodiwa ✅ Invoice {$d->document_number} sasa ni PAID", $r);
        $this->assertContains('Risiti imetumwa kwa mteja', $r);
        $p = PaymentIn::where('document_id', $d->id)->first();
        $this->assertTrue($p && (float) $p->amount === 55000.0 && $p->payment_method === 'mpesa' && $p->reference === 'TXN12345', 'payment row');
        $this->assertSame($this->staff->id, $p->received_by);
        $this->assertContains('Recorded via WhatsApp staff menu', (string) $p->notes);
        $this->assertSame('paid', $d->fresh()->status);
        $this->assertSame(1, Notification::sent($c, PaymentReceiptNotification::class)->count(), 'client receipt notification');
        $this->assertSame('staff_menu', $this->session()?->flow, 'back at staff menu');
        // a stray second "1" cannot double-record
        $this->say('1');
        $this->assertSame(1, PaymentIn::where('document_id', $d->id)->count());
    }

    public function test_partial_amount_and_overpay_refusal(): void
    {
        $c = $this->makeClient(); $d = $this->makeInvoice($c, 100000);
        $this->toMethod($d, '2'); // Benki
        $this->say('BANKREF99');
        $r = $this->say('2');
        $this->assertContains('Andika kiasi', $r);
        $r = $this->say('150,000');
        $this->assertContains('Malipo ya ziada hayarekodiwi kwa WhatsApp', $r);
        $this->assertSame('amount_other', $this->session()->state['step']);
        $r = $this->say('40000');
        $this->assertContains('Salio jipya: TZS 60,000', $r);
        $this->assertContains('Njia: Benki', $r);
        $r = $this->say('1');
        $this->assertContains('sasa ni PARTIAL, salio TZS 60,000', $r);
        $this->assertNotContains('Risiti imetumwa', $r);
        $this->assertSame('partial', $d->fresh()->status);
        $this->assertSame('bank', PaymentIn::where('document_id', $d->id)->first()->payment_method);
        $this->assertSame(0.0, (float) $c->fresh()->credit_balance, 'no credit path over WhatsApp');
    }

    public function test_pasted_sms_is_parsed_but_must_be_confirmed(): void
    {
        $c = $this->makeClient(); $d = $this->makeInvoice($c, 80000);
        $this->toMethod($d, '1');
        $r = $this->say('QGH7X8K2LM Confirmed. Tsh30,000.00 received from JOHN DOE 255712345678 on 12/9/26 at 10:15 AM. New balance is Tsh 1,200,000.00');
        $this->assertContains('Kumbukumbu: QGH7X8K2LM', $r);
        $this->assertContains('Kiasi: TZS 30,000', $r);
        $this->assertSame(0, PaymentIn::count() - PaymentIn::where('document_id', '!=', $d->id)->count(), 'nothing recorded yet');
        $r = $this->say('1');
        $this->assertContains('3) TZS 30,000 (kutoka kwenye ujumbe)', $r);
        $r = $this->say('3');
        $this->assertContains('Kiasi: TZS 30,000', $r);
        $this->assertContains('Kumbukumbu: QGH7X8K2LM', $r);
        $this->say('1');
        $this->assertSame(1, PaymentIn::where('document_id', $d->id)->where('reference', 'QGH7X8K2LM')->count());
        // rejecting the extraction goes back to manual typing
        $d2 = $this->makeInvoice($c, 1000);
        $this->say('3'); $this->say($d2->document_number); $this->say('1'); $this->say('1');
        $this->say('ABCD12345 Confirmed. Tsh1,000.00 received from X Y 0712345678');
        $r = $this->say('2');
        $this->assertContains('Andika namba ya kumbukumbu mwenyewe', $r);
        $this->assertSame('reference', $this->session()->state['step']);
    }

    public function test_duplicate_reference_refused_no_override(): void
    {
        $c = $this->makeClient(); $d1 = $this->makeInvoice($c, 10000); $d2 = $this->makeInvoice($c, 20000);
        $this->toMethod($d1, '1'); $this->say('DUPREF01'); $this->say('1'); $this->say('1');
        $this->assertSame(1, PaymentIn::where('document_id', $d1->id)->count());
        $this->say('3'); $this->say($d2->document_number); $this->say('1'); $this->say('1');
        $r = $this->say(' dupref01 ');
        $this->assertContains("Kumbukumbu hii tayari imetumika kwa Invoice {$d1->document_number}", $r);
        $this->assertSame('reference', $this->session()->state['step'], 'stays on reference step');
        $this->assertSame(0, PaymentIn::where('document_id', $d2->id)->count());
        // same reference on the other method is a different payment -> allowed to continue
        $this->say('0'); // back to method
        $this->say('2');
        $r = $this->say('DUPREF01');
        $this->assertContains('Kiasi kilicholipwa', $r);
    }

    public function test_same_amount_within_10_minutes_refused(): void
    {
        $c = $this->makeClient(); $d = $this->makeInvoice($c, 50000);
        PaymentIn::withoutGlobalScopes()->create(['tenant_id' => $this->tenant->id, 'client_id' => $c->id, 'document_id' => $d->id, 'amount' => 20000, 'payment_date' => now()->toDateString(), 'payment_method' => 'bank', 'reference' => 'OLDREF1', 'received_by' => $this->staff->id]);
        $this->toMethod($d, '1'); $this->say('NEWREF22');
        $this->say('2'); $this->say('20000');
        $r = $this->say('1');
        $this->assertContains('yalirekodiwa dakika chache zilizopita', $r);
        $this->assertSame(1, PaymentIn::where('document_id', $d->id)->count(), 'no second row');
    }

    public function test_paid_and_cancelled_invoices_are_not_offered_and_forged_state_is_refused(): void
    {
        $c = $this->makeClient();
        $paid = $this->makeInvoice($c, 1000, 'paid'); $can = $this->makeInvoice($c, 1000, 'cancelled'); $ok = $this->makeInvoice($c, 1000);
        $this->say('STAFF'); $this->say('1234'); $this->say('3');
        $r = $this->say('LIST');
        $this->assertNotContains($paid->document_number, $r);
        $this->assertNotContains($can->document_number, $r);
        $this->assertContains($ok->document_number, $r);
        $r = $this->say($paid->document_number);
        $this->assertContains('Hakuna invoice isiyolipwa', $r);
        // forged: state points at a cancelled invoice / another tenant's invoice
        $other = Tenant::withoutGlobalScopes()->where('id', '!=', $this->tenant->id)->firstOrFail();
        $fc = Client::withoutGlobalScopes()->create(['tenant_id' => $other->id, 'name' => 'Foreign', 'phone' => '255700000888', 'status' => 'active']);
        DB::table('clients')->where('id', $fc->id)->update(['tenant_id' => $other->id]);
        $fd = $this->makeInvoice($fc, 5000, 'sent', null, $other->id);
        DB::table('documents')->where('id', $fd->id)->update(['tenant_id' => $other->id]);
        foreach ([$can->id, $fd->id] as $bad) {
            $this->session()->update(['flow' => 'staff_pay', 'state' => ['step' => 'pick_invoice', 'staff_id' => $this->staff->id, 'invoice_ids' => [$bad]], 'expires_at' => now()->addMinutes(5)]);
            $r = $this->say('1');
            $this->assertContains('haipatikani tena', $r);
        }
        $this->session()->update(['flow' => 'staff_pay', 'state' => ['step' => 'confirm', 'staff_id' => $this->staff->id, 'invoice_id' => $fd->id, 'method' => 'mpesa', 'method_label' => 'x', 'reference' => 'FORGED01', 'amount' => 5]]);
        $r = $this->say('1');
        $this->assertContains('haiwezi kupokea malipo', $r);
        $this->session()->update(['flow' => 'staff_pay', 'state' => ['step' => 'confirm', 'staff_id' => $this->staff->id, 'invoice_id' => $can->id, 'method' => 'mpesa', 'method_label' => 'x', 'reference' => 'FORGED02', 'amount' => 5]]);
        $this->say('1');
        $this->assertSame(0, PaymentIn::withoutGlobalScopes()->whereIn('reference', ['FORGED01', 'FORGED02'])->count(), 'nothing recorded from forged states');
    }

    public function test_client_session_cannot_reach_the_staff_payment_flow(): void
    {
        $c = $this->makeClient(); $d = $this->makeInvoice($c, 5000);
        // a client's own verified session, tampered with staff flow state
        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $this->tenant->id, 'phone' => $this->phone],
            ['client_id' => $c->id, 'assisted_by_user_id' => null, 'flow' => 'staff_pay', 'language' => 'en', 'confirmed_at' => now(), 'expires_at' => now()->addHour(),
                'state' => ['step' => 'confirm', 'staff_id' => $this->staff->id, 'invoice_id' => $d->id, 'method' => 'mpesa', 'method_label' => 'x', 'reference' => 'CLIENTFORGE', 'amount' => 5000]],
        );
        $r = $this->say('1');
        $this->assertSame(0, PaymentIn::where('document_id', $d->id)->count(), 'no payment from a client session');
        $this->assertSame(null, $this->session(), 'tampered session dropped');
        // and a client typing 3 in their normal menu does not start staff payments
        $this->assertNotContains('Pokea Malipo', $r);
    }

    public function test_user_without_payments_in_create_is_refused(): void
    {
        $this->staff->forceFill(['role' => 'user', 'role_id' => null])->save();
        $this->say('STAFF'); $this->say('1234');
        $r = $this->say('3');
        $this->assertContains('huna ruhusa ya kurekodi malipo', $r);
        $this->assertSame('staff_menu', $this->session()->flow, 'stays on the staff menu');
    }

    public function test_menu_exits_and_back_navigation(): void
    {
        $c = $this->makeClient(); $d = $this->makeInvoice($c, 5000);
        $this->toMethod($d, '1');
        $r = $this->say('0');
        $this->assertContains('Njia ya malipo', $r);
        $this->say('1');
        $r = $this->say('MENU');
        $this->assertContains('Umetoka kwenye hali ya staff-assist', $r);
        $this->assertSame(null, $this->session());
        $this->say('STAFF'); $this->say('1234'); $this->say('3');
        $r = $this->say('RUDI');
        $this->assertContains('3) Pokea Malipo', $r);
    }

    public function test_list_caps_at_nine_with_notice(): void
    {
        $c = $this->makeClient('Cap Client');
        for ($i = 0; $i < 11; $i++) $this->makeInvoice($c, 1000 + $i);
        $this->say('STAFF'); $this->say('1234'); $this->say('3');
        $r = $this->say('Cap Client');
        $this->assertContains('9) ', $r);
        $this->assertNotContains('10) ', $r);
        $this->assertContains('Zinaonyeshwa 9 kati ya 11', $r);
    }

    public function test_reference_validation(): void
    {
        $c = $this->makeClient(); $d = $this->makeInvoice($c, 5000);
        $this->toMethod($d, '1');
        $r = $this->say('ab');
        $this->assertContains('4 hadi 40', $r);
        $this->assertSame('reference', $this->session()->state['step']);
        $r = $this->say('this has spaces but no code');
        $this->assertContains('4 hadi 40', $r);
    }
}
