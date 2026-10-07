<?php
// php tests/Manual/run_portal_otp_branding.php  (live DB, rolled back at the end)
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Http\Controllers\Portal\PortalAuthController;
use App\Models\Tenant;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

$fail = 0;
function ok($c, $m) { global $fail; if (!$c) { $fail++; echo "FAIL $m\n"; } else echo "PASS $m\n"; }

DB::beginTransaction();
try {
    $tenant = Tenant::where('custom_domain', 'luchamcloud.co.tz')->first();
    ok((bool) $tenant, 'Lucham Cloud tenant found by custom_domain');
    ok((bool) $tenant->smtp_host, 'tenant has its own SMTP host configured: ' . $tenant->smtp_host . ':' . $tenant->smtp_port);

    $email = 'otp-branding-test-' . uniqid() . '@example.com';
    $request = Request::create('https://luchamcloud.co.tz/portal/request-otp', 'POST', ['email' => $email]);
    $request->headers->set('Host', 'luchamcloud.co.tz');

    $ctl = app(PortalAuthController::class);
    $start = microtime(true);
    $response = $ctl->requestOtp($request);
    $elapsed = round(microtime(true) - $start, 2);

    ok($response->getStatusCode() === 200, "requestOtp() returns 200 even though Lucham Cloud's SMTP is unreachable: got {$response->getStatusCode()}");
    ok($elapsed < 15, "the failed SMTP attempt did not hang the request ({$elapsed}s)");

    $row = DB::table('portal_otps')->where('email', $email)->orderByDesc('created_at')->first();
    ok((bool) $row, 'the OTP row is still stored, independent of whether the email delivered');
    ok($row->tenant_id === $tenant->id, 'the OTP is scoped to the Lucham Cloud tenant (white-label by custom_domain)');

    echo $fail === 0 ? "\nALL PASS\n" : "\n{$fail} FAILURE(S)\n";
    echo "Note: this only proves the request survives Lucham Cloud's currently-unreachable SMTP.\n";
    echo "It does NOT prove the branded email was delivered — their SMTP must be fixed for that.\n";
} finally {
    DB::rollBack();
    echo "Rolled back — no permanent changes.\n";
}
