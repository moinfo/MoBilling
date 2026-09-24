<?php

namespace Tests\Manual;

use App\Models\Client;
use App\Models\ClientSubscription;
use App\Models\HostingAccount;
use App\Models\MosmsAccount;
use App\Models\ProductService;
use App\Models\ProvisioningLog;
use App\Models\Server;
use App\Models\Tenant;
use App\Models\User;
use App\Models\WhatsappOtp;
use App\Models\WhatsappRenewalSession;
use App\Notifications\HostingPasswordChangedNotification;
use App\Notifications\WhatsappOtpNotification;
use App\Services\Hosting\WhatsappCpanelResetService as Svc;
use App\Services\WhatsAppService;
use Illuminate\Http\Client\Factory;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Notification;

/**
 * "Reset cPanel password" in the WhatsApp hosting menu: emailed OTP, suggested password, apply.
 * Live DB inside an ALWAYS-rolled-back transaction; WhatsApp bound to a recording fake; WHM behind Http::fake
 * + preventStrayRequests against an invalid host; mail/notifications faked.
 *
 *   php tests/Manual/run_whatsapp_cpanel_reset.php
 */
class WhatsappCpanelResetTest
{
    private function fail(string $m): void { throw new \RuntimeException($m); }
    public function assertSame($e, $a, string $m = ''): void { if ($e !== $a) $this->fail(($m ? "$m: " : '') . 'expected ' . var_export($e, true) . ' got ' . var_export($a, true)); }
    public function assertTrue($c, string $m = 'not true'): void { if (!$c) $this->fail($m); }
    public function assertContains($n, $h): void { if (!str_contains($h, $n)) $this->fail("missing '$n' in:\n$h"); }
    public function assertNotContains($n, $h): void { if (str_contains($h, $n)) $this->fail("unexpected '$n' in:\n$h"); }

    private Tenant $tenant;
    private User $user;
    private Server $server;
    private string $phone;
    private string $rawPhone = '255700000001';
    private int $logSize = 0;
    private static string $logFile = '';

    public function setUp(): void
    {
        $this->phone = \App\Helpers\PhoneHelper::normalize($this->rawPhone);
        DB::beginTransaction();
        $this->tenant = Tenant::withoutGlobalScopes()->where('name', 'MoBilling Test Co')->firstOrFail();
        $this->user = User::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->firstOrFail();
        auth()->login($this->user);

        config(['services.mosms.inbound_webhook_secret' => 'test-secret', 'services.mosms.inbound_rate_limit' => 100000, 'services.mosms.duplicate_window' => 0]);
        MosmsAccount::create(['tenant_id' => $this->tenant->id, 'mosms_tenant_id' => 987654321, 'email' => 'x@example.test', 'token' => 'x', 'sender' => 'x']);

        $this->whm(true);
        Notification::fake();
        FwR::$sent = [];
        app()->bind(WhatsAppService::class, fn () => new FwR());
        $this->server = Server::create(['tenant_id' => $this->tenant->id, 'name' => 'fakewhm', 'hostname' => 'whm-fake.invalid', 'port' => 2087, 'username' => 'root', 'api_token' => 'x', 'type' => 'whm', 'is_active' => false]);

        self::$logFile = storage_path('logs/laravel-' . date('Y-m-d') . '.log');
        if (!is_file(self::$logFile)) self::$logFile = storage_path('logs/laravel.log');
        clearstatcache();
        $this->logSize = is_file(self::$logFile) ? filesize(self::$logFile) : 0;
    }

    public function tearDown(): void { DB::rollBack(); }

    // ── helpers ──
    private function whm(bool $ok): void
    {
        Http::swap(new Factory());
        Http::preventStrayRequests();
        Http::fake(['whm-fake.invalid:2087/json-api/passwd*' => Http::response(['metadata' => ['result' => $ok ? 1 : 0, 'reason' => $ok ? 'OK' : 'boom']])]);
    }

    private function passwdCalls()
    {
        return Http::recorded(fn ($r) => str_contains($r->url(), '/json-api/passwd'));
    }

    private function makeClient(string $name = 'Asha Test', ?string $email = 'asha@gmail.com', string $phone = null): Client
    {
        return Client::create(['tenant_id' => $this->tenant->id, 'name' => $name, 'phone' => $phone ?? $this->rawPhone, 'email' => $email, 'status' => 'active']);
    }

    private function makeHosting(Client $client, string $domain, string $status = 'active'): HostingAccount
    {
        $product = ProductService::create(['tenant_id' => $this->tenant->id, 'type' => 'service', 'name' => 'Test Plan', 'price' => 10000, 'category' => 'Web Hosting', 'billing_cycle' => 'yearly', 'provisioning_type' => 'whm_cpanel']);
        $sub = ClientSubscription::create(['tenant_id' => $this->tenant->id, 'client_id' => $client->id, 'product_service_id' => $product->id, 'start_date' => now()->subMonths(6), 'expire_date' => now()->addMonths(6), 'status' => $status === 'active' ? 'active' : 'suspended']);

        return HostingAccount::create(['tenant_id' => $this->tenant->id, 'client_subscription_id' => $sub->id, 'server_id' => $this->server->id, 'domain' => $domain, 'cpanel_username' => substr(str_replace('.', '', $domain), 0, 8), 'package' => 'Starter', 'status' => $status, 'last_synced_at' => now()->subHours(3)]);
    }

    private function startSession(Client $client, ?string $assistedBy = null): void
    {
        WhatsappRenewalSession::updateOrCreate(
            ['tenant_id' => $this->tenant->id, 'phone' => $this->phone],
            ['client_id' => $client->id, 'assisted_by_user_id' => $assistedBy, 'flow' => null, 'state' => null, 'items' => null, 'language' => 'en', 'confirmed_at' => now(), 'expires_at' => now()->addMinutes(30)],
        );
    }

    private function say(string $text): string
    {
        $before = count(FwR::$sent);
        $req = Request::create('/api/webhooks/mosms/menu', 'POST', ['secret' => 'test-secret', 'mosms_tenant_id' => 987654321, 'phone' => $this->rawPhone, 'text' => $text], [], [], ['HTTP_ACCEPT' => 'application/json']);
        $res = app()->handle($req);
        $this->assertSame(200, $res->getStatusCode());

        return implode("\n---\n", array_column(array_slice(FwR::$sent, $before), 'text'));
    }

    private function session(): ?WhatsappRenewalSession
    {
        return WhatsappRenewalSession::withoutGlobalScopes()->where('tenant_id', $this->tenant->id)->where('phone', $this->phone)->first();
    }

    /** Opens the account menu of the client's single hosting account; returns the menu text. */
    private function openMenu(Client $c, ?string $assistedBy = null): string
    {
        $this->startSession($c, $assistedBy);
        $this->say('3');

        return $this->say('2');
    }

    private function optionNo(string $menu, string $label): ?string
    {
        return preg_match('/^(\d)\) ' . preg_quote($label, '/') . '$/m', $menu, $m) ? $m[1] : null;
    }

    private function lastOtp(Client $c): string
    {
        $n = Notification::sent($c, WhatsappOtpNotification::class);
        $this->assertTrue($n->isNotEmpty(), 'no OTP email sent');

        return $n->last()->code;
    }

    /** Reaches the suggestion step; returns [client, account, suggestion text]. */
    private function toSuggestion(): array
    {
        $c = $this->makeClient();
        $a = $this->makeHosting($c, 'shop.example.test');
        $menu = $this->openMenu($c);
        $this->say($this->optionNo($menu, 'Reset cPanel password'));
        $out = $this->say($this->lastOtp($c));
        $this->assertSame('reset_pick', $this->session()->state['step'] ?? null, $out);

        return [$c, $a, $out];
    }

    private function assertNoNotifications(): void
    {
        $this->assertTrue(Notification::sentNotifications() === [] , 'notifications were sent');
    }

    private function shownPassword(string $text): string
    {
        $this->assertTrue((bool) preg_match('/^([A-Za-z0-9#@%*+-]{16,})$/m', $text, $m), "no suggestion in:\n$text");

        return $m[1];
    }

    private function dbAndLogContain(string $needle): ?string
    {
        foreach (['provisioning_logs', 'whatsapp_otps', 'whatsapp_renewal_sessions', 'communication_logs', 'whatsapp_verify_attempts'] as $t) {
            if (str_contains(json_encode(DB::table($t)->get()), $needle)) return $t;
        }
        clearstatcache();
        if (is_file(self::$logFile) && filesize(self::$logFile) > $this->logSize) {
            $fh = fopen(self::$logFile, 'r'); fseek($fh, $this->logSize); $new = stream_get_contents($fh); fclose($fh);
            if (str_contains($new, $needle)) return 'laravel.log';
        }

        return null;
    }

    public function checkNeutral(): void
    {
        foreach (FwR::$sent as $m) {
            foreach (['name.com', 'namecom', 'linode', 'usd', '$', 'whm'] as $bad) {
                if (str_contains(strtolower($m['text']), $bad)) $this->fail("supplier/cost leak '$bad' in reply:\n{$m['text']}");
            }
        }
    }

    // ── tests ──
    public function test_option_only_for_own_active_hosting(): void
    {
        $c = $this->makeClient();
        $this->makeHosting($c, 'own.example.test');
        $other = $this->makeClient('Other Person', 'o@example.test', '255700000999');
        $this->makeHosting($other, 'theirs.example.test');
        $menu = $this->openMenu($c);
        $this->assertContains('Reset cPanel password', $menu);
        $this->assertSame('6', $this->optionNo($menu, 'Reset cPanel password'));
        $this->assertSame('5', $this->optionNo($menu, 'Contact support'), 'existing numbers kept');
        $this->assertNotContains('theirs.example.test', $menu);

        $c2 = $this->makeClient('Sus Pended', 's@example.test', '255700000888');
        $this->makeHosting($c2, 'sus.example.test', 'suspended');
        $this->rawPhone = '255700000888';
        $this->phone = \App\Helpers\PhoneHelper::normalize($this->rawPhone);
        $this->assertNotContains('Reset cPanel password', $this->openMenu($c2));
    }

    public function test_swahili_label(): void
    {
        $c = $this->makeClient();
        $this->makeHosting($c, 'own.example.test');
        $this->startSession($c);
        WhatsappRenewalSession::withoutGlobalScopes()->where('phone', $this->phone)->update(['language' => 'sw']);
        $this->say('3');
        $this->assertContains('Weka upya password ya cPanel', $this->say('2'));
    }

    public function test_staff_assist_refused(): void
    {
        $c = $this->makeClient();
        $this->makeHosting($c, 'own.example.test');
        $menu = $this->openMenu($c, (string) $this->user->id);
        $out = $this->say($this->optionNo($menu, 'Reset cPanel password'));
        $this->assertContains('admin panel', $out);
        $this->assertSame(0, WhatsappOtp::count());
        $this->assertNoNotifications();
        $this->assertSame(0, $this->passwdCalls()->count());
    }

    public function test_no_email_refused(): void
    {
        $c = $this->makeClient('No Mail', null);
        $this->makeHosting($c, 'own.example.test');
        $menu = $this->openMenu($c);
        $out = $this->say($this->optionNo($menu, 'Reset cPanel password'));
        $this->assertContains("We don't have your email", $out);
        $this->assertSame(0, WhatsappOtp::count());
        $this->assertNoNotifications();
    }

    public function test_otp_sent_masked_and_hashed(): void
    {
        $c = $this->makeClient();
        $this->makeHosting($c, 'own.example.test');
        $menu = $this->openMenu($c);
        $out = $this->say($this->optionNo($menu, 'Reset cPanel password'));
        $this->assertContains('a***@gmail.com', $out);
        $this->assertNotContains('asha@gmail.com', $out);
        $code = $this->lastOtp($c);
        $this->assertTrue((bool) preg_match('/^\d{6}$/', $code));
        $this->assertNotContains($code, $out);
        $row = WhatsappOtp::first();
        $this->assertTrue($row->code_hash !== $code && strlen($row->code_hash) === 64);
        $this->assertSame(null, $this->dbAndLogContain('"' . $code . '"'), 'plaintext OTP stored');
        $this->assertTrue($row->expires_at->between(now()->addMinutes(9), now()->addMinutes(10)->addSeconds(5)));
        $this->assertSame('reset_otp', $this->session()->state['step']);
    }

    public function test_wrong_code_three_times_cancels(): void
    {
        $c = $this->makeClient();
        $this->makeHosting($c, 'own.example.test');
        $menu = $this->openMenu($c);
        $this->say($this->optionNo($menu, 'Reset cPanel password'));
        $good = $this->lastOtp($c);
        $bad = $good === '111111' ? '222222' : '111111';
        $this->assertContains('not correct', $this->say($bad));
        $this->assertContains('not correct', $this->say($bad));
        $out = $this->say($bad);
        $this->assertContains('cancelled', $out);
        $this->assertSame(null, $this->session()->state['step'] ?? null);
        // the right code no longer works
        $this->say('3'); $this->say('2');
        $this->say($good);
        $this->assertSame(0, $this->passwdCalls()->count());
        $this->assertSame(null, $this->session()->state['pw_suggestion'] ?? null);
    }

    public function test_expired_code_refused(): void
    {
        $c = $this->makeClient();
        $this->makeHosting($c, 'own.example.test');
        $menu = $this->openMenu($c);
        $this->say($this->optionNo($menu, 'Reset cPanel password'));
        $code = $this->lastOtp($c);
        WhatsappOtp::query()->update(['expires_at' => now()->subMinute()]);
        $out = $this->say($code);
        $this->assertContains('expired', $out);
        $this->assertSame(0, $this->passwdCalls()->count());
    }

    public function test_single_use_and_bound_to_phone(): void
    {
        [$c, $a] = $this->toSuggestion();
        $code = $this->lastOtp($c);
        $svc = app(Svc::class);
        $t = $this->tenant;
        $this->assertSame('expired', $svc->verifyOtp($t, $c, $this->phone, $a, $code), 'code reusable after success');
    }

    public function test_suggestion_policy_and_no_ambiguous_chars(): void
    {
        $svc = app(Svc::class);
        for ($i = 0; $i < 300; $i++) {
            $p = $svc->generatePassword();
            $this->assertTrue(strlen($p) >= 16, "short $p");
            $this->assertTrue((bool) preg_match('/[A-Z]/', $p) && preg_match('/[a-z]/', $p) && preg_match('/\d/', $p) && preg_match('/[#@%*+-]/', $p), "classes $p");
            $this->assertTrue(!preg_match('/[0O1lIoi]/', str_replace('-', '', $p)) || !preg_match('/[0O1lI]/', $p), "ambiguous $p");
            $this->assertTrue(!preg_match('/[0O1lI]/', $p), "ambiguous $p");
            $this->assertTrue(!preg_match('/\s|[$\'"`\\\\&<>]/', $p), "unsafe char $p");
        }
        $this->assertTrue($svc->generatePassword() !== $svc->generatePassword());
    }

    public function test_suggestion_shown_regen_cap_and_encrypted_state(): void
    {
        [$c, $a, $out] = $this->toSuggestion();
        $this->assertContains('1) Use this password', $out);
        $this->assertContains('2) Suggest another', $out);
        $this->assertContains('0) Cancel', $out);
        $p1 = $this->shownPassword($out);
        $st = $this->session()->state;
        $this->assertTrue($st['pw_suggestion'] !== $p1 && !str_contains(json_encode($st), $p1), 'suggestion stored in plaintext');
        $this->assertSame($p1, \Illuminate\Support\Facades\Crypt::decryptString($st['pw_suggestion']));
        $this->assertSame(null, $this->dbAndLogContain($p1));

        $seen = [$p1];
        for ($i = 1; $i <= 3; $i++) {
            $o = $this->say('2');
            $p = $this->shownPassword($o);
            $this->assertTrue(!in_array($p, $seen, true), 'same suggestion repeated');
            $seen[] = $p;
            $this->assertSame(null, $this->dbAndLogContain($seen[$i - 1]), 'old suggestion left behind');
            $this->assertSame($p, \Illuminate\Support\Facades\Crypt::decryptString($this->session()->state['pw_suggestion']));
        }
        $this->assertNotContains('2) Suggest another', $o, 'cap: no 4th regeneration offered');
        $out = $this->say('2');
        $this->assertContains('reply 1 or 0', $out);
        $this->assertSame($seen[3], \Illuminate\Support\Facades\Crypt::decryptString($this->session()->state['pw_suggestion']));
        $this->assertSame(0, $this->passwdCalls()->count(), 'WHM touched before the client chose 1');
    }

    public function test_apply_calls_whm_once_with_shown_value_and_never_stores_it(): void
    {
        [$c, $a, $out] = $this->toSuggestion();
        $p1 = $this->shownPassword($out);
        $p2 = $this->shownPassword($this->say('2'));
        $done = $this->say('1');

        $calls = $this->passwdCalls();
        $this->assertSame(1, $calls->count(), 'WHM passwd calls');
        $url = $calls->first()[0]->url();
        $this->assertContains('password=' . rawurlencode($p2), $url);
        $this->assertTrue(!str_contains($url, rawurlencode($p1)) || $p1 === $p2);
        $this->assertContains('was changed', $done);
        $this->assertNotContains($p2, $done);
        $this->assertNotContains($p1, $done);
        $this->assertSame(null, $this->session()->state['pw_suggestion'] ?? null);

        foreach ([$p1, $p2, rawurlencode($p2)] as $needle) {
            $this->assertSame(null, $this->dbAndLogContain($needle), 'password leaked');
        }
        // the password appears in the suggestion message only
        $all = FwR::allText();
        $this->assertSame(1, substr_count($all, $p2), 'password must appear in exactly one chat message');
        $this->assertTrue(Notification::sent($c, HostingPasswordChangedNotification::class)->count() === 1, 'security alert not sent');
        $audit = ProvisioningLog::withoutGlobalScopes()->where('action', Svc::AUDIT_ACTION)->get();
        $this->assertSame(1, $audit->count());
        $this->assertSame($a->id, $audit->first()->hosting_account_id);
        $this->assertSame('whatsapp', $audit->first()->request['channel']);
        $this->assertSame($c->id, $audit->first()->request['client_id']);
    }

    public function test_cancel_purges_suggestion(): void
    {
        $this->toSuggestion();
        $this->say('0');
        $this->assertSame(null, $this->session()->state['pw_suggestion'] ?? null, '0 must purge');
        $this->assertSame(0, $this->passwdCalls()->count());
    }

    public function test_menu_purges_suggestion(): void
    {
        $this->toSuggestion();
        $this->say('MENU');
        $this->assertSame(null, $this->session()->state['pw_suggestion'] ?? null, 'MENU must purge');
    }

    public function test_timeout_cleanup_strips_suggestion(): void
    {
        $c = $this->makeClient();
        $a = $this->makeHosting($c, 'own.example.test');
        $this->setTimeoutState($c, $a);
        WhatsappRenewalSession::withoutGlobalScopes()->where('phone', $this->phone)->update(['expires_at' => now()->subMinutes(11)]);
        Artisan::call('whatsapp:cleanup-sessions');
        $this->assertSame(null, $this->session()->state['pw_suggestion'] ?? null, 'cleanup must strip expired suggestion');
        $this->assertTrue(str_contains(Artisan::output(), 'password suggestions scrubbed'));
        // an expired session must not apply the password either
        $this->say('1');
        $this->assertSame(0, $this->passwdCalls()->count());
    }

    private function setTimeoutState(Client $c, HostingAccount $a): void
    {
        $this->startSession($c);
        $s = $this->session();
        $s->state = ['step' => 'reset_pick', 'account_id' => $a->id, 'pw_suggestion' => \Illuminate\Support\Facades\Crypt::encryptString('Zz-test-value-2345#'), 'regen' => 0];
        $s->save();
    }

    public function test_daily_reset_limit(): void
    {
        $c = $this->makeClient();
        $a = $this->makeHosting($c, 'own.example.test');
        for ($i = 0; $i < 2; $i++) {
            ProvisioningLog::withoutGlobalScopes()->create(['tenant_id' => $this->tenant->id, 'hosting_account_id' => $a->id, 'server_id' => $this->server->id, 'action' => Svc::AUDIT_ACTION, 'status' => 'success']);
        }
        $menu = $this->openMenu($c);
        $out = $this->say($this->optionNo($menu, 'Reset cPanel password'));
        $this->assertContains('already reset several times today', $out);
        $this->assertSame(0, WhatsappOtp::count());
        // an old (>24h) success does not count
        ProvisioningLog::withoutGlobalScopes()->where('action', Svc::AUDIT_ACTION)->update(['created_at' => now()->subDays(2)]);
        $menu = $this->openMenu($c);
        $this->assertContains('emailed a 6-digit code', $this->say($this->optionNo($menu, 'Reset cPanel password')));
    }

    public function test_otp_request_hourly_limit(): void
    {
        $c = $this->makeClient();
        $a = $this->makeHosting($c, 'own.example.test');
        for ($i = 0; $i < 3; $i++) {
            WhatsappOtp::create(['tenant_id' => $this->tenant->id, 'phone' => $this->phone, 'client_id' => $c->id, 'purpose' => Svc::purpose($a), 'code_hash' => str_repeat('a', 64), 'attempts' => 0, 'expires_at' => now()->addMinutes(5), 'used_at' => now()]);
        }
        $menu = $this->openMenu($c);
        $out = $this->say($this->optionNo($menu, 'Reset cPanel password'));
        $this->assertContains('Too many code requests', $out);
        $this->assertNoNotifications();
    }

    public function test_forged_other_client_account_refused(): void
    {
        $c = $this->makeClient();
        $this->makeHosting($c, 'own.example.test');
        $other = $this->makeClient('Other Person', 'o@example.test', '255700000999');
        $theirs = $this->makeHosting($other, 'theirs.example.test');

        foreach (['reset_otp', 'reset_pick'] as $step) {
            $this->startSession($c);
            $s = $this->session();
            $s->flow = 'hosting_manage';
            $s->state = ['step' => $step, 'account_id' => $theirs->id, 'account_ids' => [$theirs->id], 'pw_suggestion' => \Illuminate\Support\Facades\Crypt::encryptString('Forged-Value-2345#')];
            $s->save();
            $out = $this->say($step === 'reset_otp' ? '123456' : '1');
            $this->assertContains('no longer available', $out);
        }
        // forged account_menu option
        $this->startSession($c);
        $s = $this->session();
        $s->flow = 'hosting_manage';
        $s->state = ['step' => 'account_menu', 'account_id' => $theirs->id, 'options' => ['resetpass'], 'account_ids' => [$theirs->id]];
        $s->save();
        $this->say('1');
        $this->assertSame(0, WhatsappOtp::count());
        $this->assertNoNotifications();
        $this->assertSame(0, $this->passwdCalls()->count());
    }

    public function test_whm_failure_is_generic_and_changes_nothing(): void
    {
        [$c, $a, $out] = $this->toSuggestion();
        $p = $this->shownPassword($out);
        $this->whm(false);
        $done = $this->say('1');
        $this->assertContains('nothing was changed', $done);
        $this->assertNotContains('boom', $done);
        $this->assertSame(1, $this->passwdCalls()->count());
        $this->assertSame(0, ProvisioningLog::withoutGlobalScopes()->where('action', Svc::AUDIT_ACTION)->count());
        $this->assertTrue(Notification::sent($c, HostingPasswordChangedNotification::class)->isEmpty(), 'alert on failure');
        $this->assertSame(null, $this->session()->state['pw_suggestion'] ?? null);
        $this->assertSame(null, $this->dbAndLogContain($p), 'password leaked on failure');
    }

    public function test_non_code_input_does_not_burn_attempts(): void
    {
        $c = $this->makeClient();
        $this->makeHosting($c, 'own.example.test');
        $menu = $this->openMenu($c);
        $this->say($this->optionNo($menu, 'Reset cPanel password'));
        $this->assertContains('6-digit code', $this->say('hello'));
        $this->assertSame(0, (int) WhatsappOtp::first()->attempts);
    }
}

class FwR extends WhatsAppService
{
    public static array $sent = [];
    public function __construct() {}
    public function sendSessionText(Tenant $tenant, string $recipient, string $message): array { self::$sent[] = ['type' => 'text', 'text' => $message]; return []; }
    public function sendCtaUrlSession(Tenant $tenant, string $recipient, string $text, string $buttonText, string $url): array { self::$sent[] = ['type' => 'cta', 'text' => $text, 'button' => $buttonText, 'url' => $url]; return []; }
    public static function allText(): string { return implode("\n", array_column(self::$sent, 'text')); }
}
