<?php
// php tests/Manual/run_linode_costs.php  (live DB, rolled back, Linode fully faked - NO real API calls)
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Http\Controllers\LinodeController;
use App\Models\{LinodeAccount, Tenant, User};
use Illuminate\Support\Facades\{DB, Http};

$fail = 0;
function ok($c, $m) { global $fail; if (!$c) { $fail++; echo "FAIL $m\n"; } else echo "PASS $m\n"; }
DB::beginTransaction();
try {
    $t = Tenant::withoutGlobalScopes()->where('name', 'MoBilling Test Co')->firstOrFail();
    auth()->login(User::withoutGlobalScopes()->where('tenant_id', $t->id)->firstOrFail());
    $a = new LinodeAccount(['label' => 'T', 'token' => 'lin_TOKEN_abcdefghijklmnopqrstuvwxyz12', 'token_hint' => '1234', 'status' => 'active']);
    $a->tenant_id = $t->id; $a->save();

    Http::swap(new \Illuminate\Http\Client\Factory()); Http::preventStrayRequests();
    Http::fake([
        'api.linode.com/v4/account/invoices*' => Http::response(['data' => [['id' => 1, 'label' => 'Invoice #1', 'date' => '2026-07-01T00:00:00', 'total' => 10.5], ['id' => 2, 'label' => 'Invoice #2', 'date' => '2026-08-01T00:00:00', 'total' => 20]], 'pages' => 1]),
        'api.linode.com/v4/account/payments*' => Http::response(['data' => [['id' => 9, 'date' => '2026-08-02T00:00:00', 'usd' => 30.5]], 'pages' => 1]),
        'api.linode.com/v4/account' => Http::response(['balance' => 0, 'balance_uninvoiced' => 4.25]),
    ]);
    $d = app(LinodeController::class)->costs()->getData(true)['data'];
    $row = collect($d)->firstWhere('label', 'T');
    ok(count($row['invoices']) === 2 && $row['invoices'][0]['id'] === 2, 'invoices listed newest first');
    ok(abs($row['payments'][0]['usd'] - 30.5) < 0.001 && $row['balance_uninvoiced'] == 4.25, 'payments + uninvoiced balance');
    ok(Http::recorded(fn ($r) => $r->method() !== 'GET')->count() === 0, 'only GET requests made');
    ok(!str_contains(json_encode($d), 'lin_TOKEN'), 'token not in response');

    Http::swap(new \Illuminate\Http\Client\Factory()); Http::preventStrayRequests();
    Http::fake(['api.linode.com/v4/*' => Http::response(['errors' => [['reason' => 'Unauthorized']]], 403)]);
    $row = collect(app(LinodeController::class)->costs()->getData(true)['data'])->firstWhere('label', 'T');
    ok(str_contains($row['error'] ?? '', 'account:read_only'), '403 gives a clear missing-scope message');

    Http::swap(new \Illuminate\Http\Client\Factory()); Http::preventStrayRequests();
    Http::fake(['api.linode.com/v4/account/invoices/77/items*' => Http::response(['data' => [['label' => 'Nanode', 'from' => '2026-09-01', 'to' => '2026-09-30', 'quantity' => 1, 'unit_price' => '5', 'amount' => 5, 'tax' => 0, 'total' => 5]], 'pages' => 1])]);
    $resp = app(LinodeController::class)->downloadInvoice($a, '77');
    ob_start(); $resp->sendContent(); $csv = ob_get_clean();
    ok(str_contains($csv, 'Nanode') && str_contains($csv, '5.00'), 'invoice CSV has items and total');
    ok(Http::recorded(fn ($r) => $r->method() !== 'GET')->count() === 0, 'download is GET only');
} finally { DB::rollBack(); }
echo $fail ? "FAILED $fail\n" : "ALL PASSED\n";
