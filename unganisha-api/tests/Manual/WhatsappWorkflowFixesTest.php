<?php

namespace Tests\Manual;

use App\Models\Client;
use App\Models\Document;
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
        config(['services.mosms.inbound_webhook_secret' => 'test-secret', 'services.mosms.duplicate_window' => 0]);
        MosmsAccount::create(['tenant_id' => $this->tenant->id, 'mosms_tenant_id' => 987654321, 'email' => 'x@example.test', 'token' => 'x', 'sender' => 'x']);
        Http::swap(new Factory());
        Http::preventStrayRequests();
        Http::fake([]);
        Notification::fake();
        // cache is the DB driver: writes roll back with the transaction, never flush the live cache
        \Illuminate\Support\Facades\Cache::forget("wa_inbound_rl:{$this->tenant->id}:{$this->phone}");
        \Illuminate\Support\Facades\Cache::forget("wa_bot_send_alert:{$this->tenant->id}");
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

    // ── Fix 2: yes/no parsing everywhere ──
    private function atStep(string $step, bool $withClient = true): void
    {
        $c = $withClient ? $this->makeClientOnce() : null;
        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $this->tenant->id, 'phone' => $this->phone],
            ['client_id' => $c?->id, 'flow' => null, 'state' => ['step' => $step], 'items' => null, 'language' => 'sw', 'confirmed_at' => null, 'attempts' => 0, 'expires_at' => now()->addMinutes(10)],
        );
    }

    public function test_h3_has_account_accepts_all_yes_forms(): void
    {
        foreach (['1', 'ndio', 'Ndiyo.', ' YES ', 'sawa', 'ok', 'y', 'Yes!', 'ndiyo 👍'] as $in) {
            $this->atStep('has_account');
            $t = $this->say($in);
            $this->assertContains('jina lako la ukoo', $t);
            $this->assertSame('surname', $this->session()?->state['step'] ?? null, $in);
        }
    }

    public function test_h3_has_account_no_goes_to_want_account_and_gibberish_reprompts(): void
    {
        $this->atStep('has_account');
        $t = $this->say('asdf');
        $this->assertContains('Jibu 1 au 2', str_replace('jibu 1 au 2', 'Jibu 1 au 2', $t));
        $this->assertSame('has_account', $this->session()?->state['step'] ?? null, 'state kept on gibberish');
        $this->say('hapana');
        $this->assertSame('want_account', $this->session()?->state['step'] ?? null);
    }

    public function test_h3_want_account_gibberish_reprompts_and_only_explicit_no_cancels(): void
    {
        $this->atStep('want_account');
        $t = $this->say('labda');
        $this->assertContains('jibu 1 au 2', $t);
        $this->assertTrue($this->session() !== null, 'session kept');
        $this->say('hapana');
        $this->assertSame(null, $this->session(), 'explicit no cancels');

    }

    public function test_h3_want_account_yes_forms_start_registration_and_n_cancels(): void
    {
        $this->atStep('want_account', false);
        $this->say(' Sawa ');
        $this->assertSame('register', $this->session()?->flow, 'yes starts registration');

        $this->atStep('want_account', false);
        $this->say('N');
        $this->assertSame(null, $this->session());
    }

    // ── Fix 3: friendly errors ──
    private function domainWithHosting(Client $c, string $name, int $days): array
    {
        $d = \App\Models\Domain::create(['tenant_id' => $this->tenant->id, 'client_id' => $c->id, 'name' => $name, 'status' => 'active', 'expires_at' => now()->addDays($days), 'meta' => ['unmanaged' => true]]);
        $server = \App\Models\Server::withoutGlobalScopes()->first() ?? \App\Models\Server::create(['tenant_id' => $this->tenant->id, 'name' => 'fake', 'hostname' => 'fake.invalid', 'port' => 2087, 'username' => 'root', 'api_token' => 'x', 'type' => 'whm', 'is_active' => false]);
        $product = \App\Models\ProductService::create(['tenant_id' => $this->tenant->id, 'type' => 'service', 'name' => 'Test Plan', 'price' => 10000, 'tax_percent' => 0, 'unit' => 'pcs', 'category' => 'Web Hosting', 'billing_cycle' => 'yearly', 'provisioning_type' => 'whm_cpanel']);
        $sub = \App\Models\ClientSubscription::create(['tenant_id' => $this->tenant->id, 'client_id' => $c->id, 'product_service_id' => $product->id, 'label' => $name, 'quantity' => 1, 'start_date' => now()->subMonths(12)->addDays($days), 'expire_date' => now()->addDays($days), 'status' => 'active']);
        \App\Models\HostingAccount::create(['tenant_id' => $this->tenant->id, 'client_subscription_id' => $sub->id, 'server_id' => $server->id, 'domain' => $name, 'cpanel_username' => substr(str_replace('.', '', $name), 0, 8), 'package' => 'Starter', 'status' => 'active', 'last_synced_at' => now(), 'meta' => []]);
        return [$d, $sub];
    }

    public function test_m3_existing_open_invoice_is_shown_instead_of_raw_error(): void
    {
        $c = $this->makeClient();
        [$d, $sub] = $this->domainWithHosting($c, 'wf-open.test', 10);
        $inv = Document::withoutGlobalScopes()->create(['tenant_id' => $this->tenant->id, 'client_id' => $c->id, 'type' => 'invoice', 'document_number' => 'T-WF1', 'date' => now()->toDateString(), 'due_date' => now()->addDays(5)->toDateString(), 'subtotal' => 5000, 'discount_amount' => 0, 'tax_amount' => 0, 'total' => 5000, 'status' => 'sent']);
        \App\Models\RecurringInvoiceLog::create(['tenant_id' => $this->tenant->id, 'client_id' => $c->id, 'product_service_id' => $sub->product_service_id, 'client_subscription_id' => $sub->id, 'document_id' => $inv->id, 'next_bill_date' => now()->addYear(), 'invoice_created_at' => now(), 'reminders_sent' => []]);
        $this->startSession($c, ['items' => [$d->id]]);
        $t = $this->hit('renewal-reply', '1');
        $this->assertNotContains('already has a current invoice', $t);
        $this->assertNotContains('Everything for this domain', $t);
        $this->assertSame('pay_invoice', $this->session()?->flow);
        $this->assertSame($inv->id, $this->session()?->state['document_id'] ?? null);
        $this->assertContains('T-WF1', $t);
    }

    public function test_m3_current_invoice_but_nothing_open_gets_friendly_message(): void
    {
        $c = $this->makeClient();
        [$d, $sub] = $this->domainWithHosting($c, 'wf-paid.test', 10);
        $inv = Document::withoutGlobalScopes()->create(['tenant_id' => $this->tenant->id, 'client_id' => $c->id, 'type' => 'invoice', 'document_number' => 'T-WF2', 'date' => now()->toDateString(), 'due_date' => now()->addDays(5)->toDateString(), 'subtotal' => 5000, 'discount_amount' => 0, 'tax_amount' => 0, 'total' => 5000, 'status' => 'paid']);
        \App\Models\RecurringInvoiceLog::create(['tenant_id' => $this->tenant->id, 'client_id' => $c->id, 'product_service_id' => $sub->product_service_id, 'client_subscription_id' => $sub->id, 'document_id' => $inv->id, 'next_bill_date' => now()->addYear(), 'invoice_created_at' => now(), 'reminders_sent' => []]);
        $this->startSession($c, ['items' => [$d->id]]);
        $t = $this->hit('renewal-reply', '1');
        $this->assertNotContains('already has a current invoice', $t);
        $this->assertContains('nothing to pay right now', $t);
    }

    public function test_m3_unknown_exception_text_never_reaches_client(): void
    {
        $c = $this->makeClient();
        $d = \App\Models\Domain::create(['tenant_id' => $this->tenant->id, 'client_id' => $c->id, 'name' => 'wf-boom.test', 'status' => 'active', 'expires_at' => now()->addDays(10), 'meta' => ['unmanaged' => true]]);
        app()->bind(\App\Services\Hosting\RenewalBundleService::class, fn () => new class extends \App\Services\Hosting\RenewalBundleService {
            public function generate(\App\Models\HostingAccount $h, bool $selfService = false): Document { throw new \RuntimeException('SQLSTATE[HY000] secret internals namecom'); }
        });
        $this->startSession($c, ['items' => [$d->id]]);
        $t = $this->hit('renewal-reply', '1');
        $this->assertNotContains('SQLSTATE', $t);
        $this->assertNotContains('secret internals', $t);
        $this->assertContains("couldn't complete this request", $t);
    }

    // ── Fix 4: MENU everywhere, timeout notice, logout, window-passed hint ──
    public function test_l2_menu_words_work_in_every_unverified_state(): void
    {
        $c = $this->makeClientOnce();
        foreach (['MENU', 'cancel', 'Nyumbani', 'anza upya'] as $word) {
            foreach (['language_select', 'register', 'surname', 'has_account', 'want_account'] as $st) {
                WhatsappRenewalSession::updateOrCreate(
                    ['tenant_id' => $this->tenant->id, 'phone' => $this->phone],
                    ['client_id' => $c->id, 'flow' => in_array($st, ['language_select', 'register']) ? $st : null, 'state' => ['step' => $st === 'register' ? 'ask_name' : $st], 'items' => null, 'language' => $st === 'language_select' ? null : 'en', 'confirmed_at' => null, 'attempts' => 0, 'expires_at' => now()->addMinutes(10)],
                );
                $t = $this->say($word);
                $this->assertContains('1) English', $t);
                $this->assertSame('language_select', $this->session()?->flow, "$word in $st");
                $this->assertSame(0, (int) $this->session()?->attempts);
            }
        }
    }

    public function test_l2_menu_in_staff_pin_exits_without_counting_wrong_pin(): void
    {
        $this->user->update(['phone' => $this->rawPhone, 'is_active' => true, 'whatsapp_pin_hash' => \Illuminate\Support\Facades\Hash::make('1234')]);
        $t = $this->say('STAFF');
        $this->assertContains('PIN', $t);
        $this->assertSame('staff_pin', $this->session()?->flow);
        foreach (['MENU', 'nyumbani', 'anza upya', 'cancel'] as $w) {
            $this->say('STAFF');
            $t = $this->say($w);
            $this->assertNotContains('PIN si sahihi', $t);
            $this->assertSame(null, $this->session(), "$w exits staff mode");
        }
    }

    public function test_l4_expired_session_says_timed_out_once_then_language(): void
    {
        $c = $this->makeClientOnce();
        $this->startSession($c, ['language' => 'en', 'expires_at' => now()->subMinute()]);
        $t = $this->say('hello');
        $this->assertContains("Your session timed out, let's start again.", $t);
        $this->assertContains('1) English', $t);
        $t2 = $this->say('zzz');
        $this->assertNotContains('timed out', $t2);

        $this->startSession($c, ['language' => 'sw', 'expires_at' => now()->subMinute()]);
        $this->assertContains('Muda wa kikao umeisha, tuanze upya.', $this->say('hi'));
    }

    public function test_l5_logout_message_and_window_passed_menu_hint(): void
    {
        $c = $this->makeClientOnce();
        $this->startSession($c, ['language' => 'sw']);
        $this->assertContains('Umetoka. Andika MOBILLING kuanza tena.', $this->say('0'));
        $this->startSession($c, ['language' => 'en']);
        $this->assertContains('Type MOBILLING to start again.', $this->say('0'));
        $this->assertSame(null, $this->session());

        $t = $this->hit('renewal-reply', '1'); // no session at all
        $this->assertContains('Andika MENU', $t);
        $this->startSession($c, ['language' => 'sw', 'items' => ['x'], 'expires_at' => now()->subMinute()]);
        $this->assertContains('Andika MENU', $this->hit('renewal-reply', '1'));
    }

    // ── Fix 5: reliability / abuse ──
    public function test_m7_send_failure_logs_and_alerts_staff_once_per_hour(): void
    {
        $logged = [];
        \Illuminate\Support\Facades\Log::listen(function ($e) use (&$logged) { $logged[] = [$e->message, $e->context]; });
        $c = $this->makeClientOnce();
        $this->startSession($c);
        Wf::$failMessage = 'MoSMS: Insufficient WhatsApp balance';
        Wf::$fail = true;
        $this->say('zzz');
        $this->say('zzz');
        Wf::$fail = false;
        $hit = array_filter($logged, fn ($l) => str_contains($l[0], 'send failed') && ($l[1]['phone'] ?? null) === $this->phone && ($l[1]['tenant_id'] ?? null) === $this->tenant->id);
        $this->assertTrue(count($hit) >= 1, 'failure logged with tenant/phone');
        $this->assertSame(1, Notification::sent($this->user, \App\Notifications\WhatsappBotAlertNotification::class)->count());
        Wf::$failMessage = 'WhatsApp send failed (fake)';
    }

    public function test_m7_non_balance_failure_does_not_alert(): void
    {
        $c = $this->makeClientOnce();
        $this->startSession($c);
        Wf::$fail = true;
        $this->say('zzz');
        Wf::$fail = false;
        $this->assertSame(0, Notification::sent($this->user, \App\Notifications\WhatsappBotAlertNotification::class)->count());
    }

    public function test_m7_rate_limit_31st_gets_notice_then_silence(): void
    {
        config(['services.mosms.inbound_rate_limit' => 30]);
        $c = $this->makeClientOnce();
        $this->startSession($c);
        for ($i = 1; $i <= 30; $i++) $this->say('zzz');
        $this->assertSame(30, count(Wf::$sent));
        $t = $this->say('zzz');
        $this->assertContains('Tafadhali subiri kidogo', $t);
        $this->assertSame('', $this->say('zzz'), '32nd is dropped silently');
        $this->assertSame('', $this->hit('renewal-reply', '1'), 'renewal-reply counts too');
        // another phone is unaffected
        $cache = \Illuminate\Support\Facades\Cache::get("wa_inbound_rl:{$this->tenant->id}:255700000009");
        $this->assertSame(null, $cache);
    }

    public function test_m7_long_reply_split_on_line_boundaries(): void
    {
        $ref = new \ReflectionMethod(\App\Http\Controllers\WhatsappRenewalWebhookController::class, 'splitMessage');
        $ref->setAccessible(true);
        $ctl = app(\App\Http\Controllers\WhatsappRenewalWebhookController::class);
        $lines = [];
        for ($i = 0; $i < 400; $i++) $lines[] = str_pad("line $i ", 30, 'x');
        $msg = implode("\n", $lines);
        $parts = $ref->invoke($ctl, $msg);
        $this->assertTrue(count($parts) > 1, 'split');
        foreach ($parts as $p) $this->assertTrue(mb_strlen($p) <= 3900, 'part too long');
        $this->assertSame($msg, implode("\n", $parts), 'nothing lost, lines intact');
        $this->assertSame(['short'], $ref->invoke($ctl, 'short'));
        $one = str_repeat('a', 9000);
        $this->assertSame($one, implode('', $ref->invoke($ctl, $one)), 'single long line hard-cut');
    }

    // ── Fix 6: media marker ──
    public function test_h2_media_marker_replies_notifies_staff_and_keeps_state(): void
    {
        $c = $this->makeClientOnce();
        $this->startSession($c, ['flow' => 'whois', 'state' => ['step' => 'ask_name'], 'language' => 'en']);
        $before = $this->session()->only(['flow', 'state', 'language']);
        foreach (['[media]', '[unsupported]'] as $m) {
            $t = $this->say($m);
            $this->assertContains('We only accept text messages for now', $t);
            $this->assertSame($before, $this->session()->only(['flow', 'state', 'language']), 'state untouched');
        }
        $this->assertTrue(Notification::sent($this->user, \App\Notifications\WhatsappBotAlertNotification::class)->count() >= 2, 'staff notified');
        $n = Notification::sent($this->user, \App\Notifications\WhatsappBotAlertNotification::class)->first();
        $this->assertContains($c->name, $n->message);

        $this->startSession($c, ['language' => 'sw']);
        $this->assertContains('Tunapokea ujumbe wa maandishi tu kwa sasa. Kwa risiti au picha, tafadhali wasiliana na staff wetu.', $this->say('[media]'));
    }

    public function test_h2_media_with_no_session_never_crashes(): void
    {
        $t = $this->say('[MEDIA]');
        $this->assertContains('Tunapokea ujumbe wa maandishi tu', $t);
        $this->assertContains('We only accept text messages', $t);
        $this->assertSame(null, $this->session());
    }
}

class Wf extends WhatsAppService
{
    public static array $sent = [];
    public static bool $fail = false;
    public static string $failMessage = 'WhatsApp send failed (fake)';
    public function __construct() {}
    public function sendSessionText(Tenant $tenant, string $recipient, string $message): array
    {
        if (self::$fail) throw new \RuntimeException(self::$failMessage);
        self::$sent[] = ['type' => 'text', 'text' => $message]; return [];
    }
    public function sendCtaUrlSession(Tenant $tenant, string $recipient, string $text, string $buttonText, string $url): array
    {
        if (self::$fail) throw new \RuntimeException(self::$failMessage);
        self::$sent[] = ['type' => 'cta', 'text' => $text, 'button' => $buttonText, 'url' => $url]; return [];
    }
}
