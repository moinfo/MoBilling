<?php
// php tests/Manual/run_system_verification_figures.php  (live DB, rolled back at the end)
// Run AFTER `php artisan migrate` has applied the three new migrations for
// this feature (login credentials, verification window, report figures).
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Http\Controllers\SystemVerificationController;
use App\Models\SystemVerification;
use App\Models\Tenant;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

$fail = 0;
function ok($c, $m) { global $fail; if (!$c) { $fail++; echo "FAIL $m\n"; } else echo "PASS $m\n"; }
function req(Request $rq, $u) { $rq->setUserResolver(fn () => $u); app()->instance('request', $rq); auth()->setUser($u); return $rq; }

DB::beginTransaction();
try {
    $tenant = Tenant::find('019c8f39-679e-70d2-af92-ac72a25b0d9c'); // Moinfotech Company Limited
    $owner = User::where('tenant_id', $tenant->id)->where('is_active', true)->get()
        ->first(fn ($u) => $u->hasPermission('system_verifications.update'));
    ok((bool) $owner, 'have a system_verifications.update user to test with');

    $staff = User::where('tenant_id', $tenant->id)->where('is_active', true)
        ->where('id', '!=', $owner->id)->first();
    ok((bool) $staff, 'have a second user to assign as the checker');

    $ctl = app(SystemVerificationController::class);

    // 1. Login credentials round-trip through encryption correctly. Window is
    // set per-system here too — each assigned person can have their own.
    $sv = SystemVerification::create([
        'tenant_id' => $tenant->id,
        'name' => 'Test POS — figures script',
        'domain_name' => 'test-pos.example.com',
        'login_username' => 'cashier1',
        'login_password' => 'S3cret!42',
        'window_from' => '08:00',
        'window_to' => '09:00',
        'assigned_user_id' => $staff->id,
        'is_active' => true,
    ]);
    $fresh = SystemVerification::find($sv->id);
    ok($fresh->login_username === 'cashier1', 'login_username stored as given');
    ok($fresh->login_password === 'S3cret!42', 'login_password decrypts back to the original value');
    $rawRow = DB::table('system_verifications')->where('id', $sv->id)->value('login_password');
    ok($rawRow !== 'S3cret!42', 'login_password is NOT stored in plaintext in the database');
    ok($fresh->window_from === '08:00:00', 'this system\'s own window_from saved');

    // 2. A second system, assigned to the same staff, with a DIFFERENT window —
    // proving the window really is per-system/per-person, not tenant-wide.
    $sv2 = SystemVerification::create([
        'tenant_id' => $tenant->id,
        'name' => 'Test POS 2 — figures script',
        'assigned_user_id' => $staff->id,
        'window_from' => '14:00',
        'window_to' => '15:00',
        'is_active' => true,
    ]);

    $withinWindow = (new ReflectionMethod($ctl, 'isWithinVerificationWindow'));
    $withinWindow->setAccessible(true);

    \Illuminate\Support\Facades\Date::setTestNow('2026-01-01 08:30:00');
    ok($withinWindow->invoke($ctl, $sv->fresh()) === true, 'at 08:30, system 1 (08:00-09:00) is within its own window');
    ok($withinWindow->invoke($ctl, $sv2->fresh()) === false, 'at the SAME moment, system 2 (14:00-15:00) is late against ITS OWN, different window');
    \Illuminate\Support\Facades\Date::setTestNow();

    // No window set on a system: nothing to judge against.
    $sv3 = SystemVerification::create(['tenant_id' => $tenant->id, 'name' => 'Test POS 3 — no window', 'is_active' => true]);
    ok($withinWindow->invoke($ctl, $sv3->fresh()) === null, 'a system with no window configured is null (not tracked), not false');

    // 3. Submitting today's report requires the four figures and records them.
    req(Request::create('/x', 'POST', [
        'status' => 'ok', 'cash' => 150000, 'sales' => 500000, 'credit' => 50000, 'gain_loss' => -2500,
    ]), $staff);
    $formReq = app(\App\Http\Requests\StoreSystemVerificationReportRequest::class);
    $resp = $ctl->submitReport($formReq, $sv->fresh());
    $data = json_decode($resp->toJson(), true)['data'] ?? json_decode($resp->toJson(), true);
    ok((float) ($data['cash'] ?? 0) == 150000, 'cash recorded on the report');
    ok((float) ($data['gain_loss'] ?? 0) == -2500, 'a negative gain_loss (a loss) is stored correctly');

    $missing = Request::create('/x', 'POST', ['status' => 'ok']); // no figures at all
    try {
        app(\Illuminate\Contracts\Validation\Factory::class);
        $missing->setUserResolver(fn () => $staff);
        app()->instance('request', $missing);
        auth()->setUser($staff);
        $fr2 = app(\App\Http\Requests\StoreSystemVerificationReportRequest::class);
        $fr2->validateResolved();
        ok(false, 'submitting without cash/sales/credit/gain_loss should be rejected');
    } catch (\Illuminate\Validation\ValidationException $e) {
        $errs = array_keys($e->errors());
        ok(in_array('cash', $errs) && in_array('sales', $errs) && in_array('credit', $errs) && in_array('gain_loss', $errs),
            'missing figures are rejected by validation: ' . implode(',', $errs));
    }

    echo $fail === 0 ? "\nALL PASS\n" : "\n{$fail} FAILURE(S)\n";
} finally {
    DB::rollBack();
    echo "Rolled back — no permanent changes.\n";
}
