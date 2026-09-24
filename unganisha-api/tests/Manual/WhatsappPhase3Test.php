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
}
