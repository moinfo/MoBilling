<?php
// php tests/Manual/run_wallet_topup_platform_pesapal.php  (live DB, rolled back at the end)
//
// Verifies the fix: a reseller tenant's wallet top-up pays MoBilling's own
// Pesapal account (config/pesapal.php), never the tenant's own — and that
// the credit actually lands on the tenant's wallet via the platform webhook.
// Does NOT call Pesapal's live API (submitOrder/getTransactionStatus) —
// that would create a real order in MoBilling's own production account.
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Http\Controllers\PesapalWebhookController;
use App\Http\Controllers\TenantWalletController;
use App\Models\Tenant;
use App\Models\TenantWalletTopup;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

$fail = 0;
function ok($c, $m) { global $fail; if (!$c) { $fail++; echo "FAIL $m\n"; } else echo "PASS $m\n"; }
function req(Request $rq, $u) { $rq->setUserResolver(fn () => $u); app()->instance('request', $rq); auth()->setUser($u); return $rq; }

DB::beginTransaction();
try {
    $src = file_get_contents(__DIR__ . '/../../app/Http/Controllers/TenantWalletController.php');
    ok(!str_contains($src, 'TenantPesapalService'), 'TenantWalletController no longer uses the tenant\'s own Pesapal service at all');
    ok(substr_count($src, 'new PesapalService()') === 2, 'topupPesapal() and topupStatus() both use the platform PesapalService');

    $webhookSrc = file_get_contents(__DIR__ . '/../../app/Http/Controllers/TenantPesapalWebhookController.php');
    ok(!str_contains($webhookSrc, 'TenantWalletTopup'), 'the tenant-scoped webhook no longer handles wallet top-ups at all');

    $tenant = Tenant::find('01a0f22f-45f9-733f-a519-1d5a47cbe6e7'); // Lucham Cloud
    ok((bool) $tenant, 'Lucham Cloud tenant found');
    ok($tenant->is_wallet_gated, 'Lucham Cloud is wallet-gated');

    // pesapal_configured must now be TRUE even though the tenant's OWN pesapal_enabled is false —
    // the whole point: this no longer depends on the tenant's own Pesapal setup.
    ok(!$tenant->pesapal_enabled, 'sanity check: the tenant\'s OWN Pesapal is still off (unrelated to this fix)');
    $owner = User::where('tenant_id', $tenant->id)->where('role', 'admin')->first();
    $resp = app(TenantWalletController::class)->show(req(Request::create('/x', 'GET'), $owner));
    $data = $resp->getData(true)['data'];
    ok($data['pesapal_configured'] === true, 'Wallet page now shows top-up available via the PLATFORM account, independent of the tenant\'s own Pesapal state');

    // Simulate what the platform IPN does on a completed top-up — without calling Pesapal's live API.
    $before = (float) $tenant->fresh()->wallet_balance;
    $topup = TenantWalletTopup::withoutGlobalScopes()->create([
        'tenant_id' => $tenant->id,
        'requested_by' => $owner->id,
        'amount' => 25000,
        'status' => 'pending',
        'order_tracking_id' => 'TEST-' . uniqid(),
        'confirmation_code' => 'TESTCONF123',
        'payment_method_used' => 'TEST',
    ]);

    $ref = new ReflectionMethod(PesapalWebhookController::class, 'processWalletTopupCompleted');
    $ref->setAccessible(true);
    $ref->invoke(new PesapalWebhookController(), $topup);

    $after = (float) $tenant->fresh()->wallet_balance;
    ok(round($after - $before, 2) === 25000.0, "wallet credited by exactly the top-up amount: {$before} -> {$after}");
    ok($topup->fresh()->status === 'completed', 'the top-up row is marked completed');

    $before2 = (float) $tenant->fresh()->wallet_balance;
    $ref->invoke(new PesapalWebhookController(), $topup->fresh());
    $after2 = (float) $tenant->fresh()->wallet_balance;
    ok($before2 === $after2, 'a duplicate/replayed IPN does not credit the wallet twice');

    echo $fail === 0 ? "\nALL PASS\n" : "\n{$fail} FAILURE(S)\n";
} finally {
    DB::rollBack();
    echo "Rolled back — no permanent changes.\n";
}
