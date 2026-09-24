<?php

namespace Tests\Manual;

use App\Models\Client;
use App\Models\MosmsAccount;
use App\Models\Tenant;
use App\Models\User;
use App\Models\WhatsappRenewalSession;
use App\Services\WhatsAppService;
use Illuminate\Http\Client\Factory;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Notification;

/**
 * WhatsApp workflow fixes (bare-1 hijack, yes/no parsing, friendly errors, MENU everywhere, reliability, media).
 * Live DB inside an ALWAYS-rolled-back transaction; WhatsApp is a recording fake; every HTTP call is blocked.
 *
 *   php tests/Manual/run_whatsapp_workflow_fixes.php
 */
class WhatsappWorkflowFixesTest
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
        $this->tenant = Tenant::withoutGlobalScopes()->where('name', 'MoBilling Test Co')->firstOrFail();
        $this->user = User::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->firstOrFail();
        auth()->login($this->user);
        config(['services.mosms.inbound_webhook_secret' => 'test-secret']);
        MosmsAccount::create(['tenant_id' => $this->tenant->id, 'mosms_tenant_id' => 987654321, 'email' => 'x@example.test', 'token' => 'x', 'sender' => 'x']);
        Http::swap(new Factory());
        Http::preventStrayRequests();
        Http::fake([]);
        Notification::fake();
        \Illuminate\Support\Facades\Cache::flush();
        Wf::$sent = [];
        Wf::$fail = false;
        app()->bind(WhatsAppService::class, fn () => new Wf());
    }

    public function tearDown(): void { DB::rollBack(); }

    // ── helpers ──
    private function makeClient(string $name = 'Asha Test'): Client
    {
        return Client::create(['tenant_id' => $this->tenant->id, 'name' => $name, 'phone' => $this->rawPhone, 'email' => strtolower(str_replace(' ', '', $name)) . '@example.test', 'status' => 'active']);
    }

    private function startSession(Client $client, array $extra = []): void
    {
        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $this->tenant->id, 'phone' => $this->phone],
            array_merge(['client_id' => $client->id, 'assisted_by_user_id' => null, 'flow' => null, 'state' => null, 'items' => null, 'language' => 'en', 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(30)], $extra),
        );
    }

    private function hit(string $route, string $text): string
    {
        $before = count(Wf::$sent);
        $req = Request::create("/api/webhooks/mosms/$route", 'POST', ['secret' => 'test-secret', 'mosms_tenant_id' => 987654321, 'phone' => $this->rawPhone, 'text' => $text], [], [], ['HTTP_ACCEPT' => 'application/json']);
        $res = app()->handle($req);
        $this->assertSame(200, $res->getStatusCode());
        return implode("\n---\n", array_column(array_slice(Wf::$sent, $before), 'text'));
    }
    private function say(string $text): string { return $this->hit('menu', $text); }
    private function session(): ?WhatsappRenewalSession
    {
        return WhatsappRenewalSession::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->where('phone', $this->phone)->first();
    }

    public function checkNeutral(): void
    {
        foreach (Wf::$sent as $m) {
            foreach (['name.com', 'namecom', 'linode', 'usd', '$'] as $bad) {
                if (str_contains(strtolower($m['text']), $bad)) $this->fail("supplier/cost leak '$bad' in reply:\n{$m['text']}");
            }
        }
    }

    // ── Fix 1: bare '1' hijack ──
    public function test_h1_bare_one_in_language_select_is_english_not_window_passed(): void
    {
        $this->makeClient();
        $this->startSession($this->makeClientOnce(), ['flow' => 'language_select', 'confirmed_at' => null, 'language' => null, 'items' => ['x']]);
        $t = $this->hit('renewal-reply', '1');
        $this->assertNotContains('reply window has passed', $t);
        $this->assertNotContains('muda wa kujibu umepita', $t);
        $this->assertTrue($t !== '', 'some reply');
    }

    private ?Client $c = null;
    private function makeClientOnce(): Client
    {
        return $this->c ??= Client::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->where('phone', $this->rawPhone)->first() ?? $this->makeClient();
    }

    public function test_h1_bare_one_inside_a_flow_acts_as_menu_digit(): void
    {
        $c = $this->makeClient();
        $this->startSession($c);
        $this->say('zzz'); // root menu
        $this->startSession($c, ['flow' => null, 'items' => null]);
        $t = $this->hit('renewal-reply', '1'); // root '1' => Domain Registration
        $this->assertNotContains('window has passed', $t);
        $this->assertSame('order_domain', $this->session()?->flow);
    }

    public function test_h1_bare_one_with_empty_items_and_no_flow_is_menu_digit(): void
    {
        $c = $this->makeClient();
        $this->startSession($c, ['items' => []]);
        $this->hit('renewal-reply', '1');
        $this->assertSame('order_domain', $this->session()?->flow);
    }

    public function test_h1_genuine_renewal_reply_still_works(): void
    {
        $c = $this->makeClient();
        $this->startSession($c, ['items' => ['00000000-0000-0000-0000-000000000000']]);
        $t = $this->hit('renewal-reply', '1');
        $this->assertContains('no longer available', $t); // reached pickAndGenerate, not the menu
        $this->assertTrue($this->session()?->flow !== 'order_domain', 'not routed to menu');
    }
}

class Wf extends WhatsAppService
{
    public static array $sent = [];
    public static bool $fail = false;
    public function __construct() {}
    public function sendSessionText(Tenant $tenant, string $recipient, string $message): array
    {
        if (self::$fail) throw new \RuntimeException('WhatsApp send failed (fake)');
        self::$sent[] = ['type' => 'text', 'text' => $message]; return [];
    }
    public function sendCtaUrlSession(Tenant $tenant, string $recipient, string $text, string $buttonText, string $url): array
    {
        if (self::$fail) throw new \RuntimeException('WhatsApp send failed (fake)');
        self::$sent[] = ['type' => 'cta', 'text' => $text, 'button' => $buttonText, 'url' => $url]; return [];
    }
}
