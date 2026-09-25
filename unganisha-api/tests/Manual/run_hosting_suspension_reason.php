<?php
// php tests/Manual/run_hosting_suspension_reason.php  (pure model logic, no DB writes, no external calls)
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Models\{ClientSubscription, HostingAccount};

$fail = 0;
function ok($c, $m) { global $fail; if (!$c) { $fail++; echo "FAIL $m\n"; } else echo "PASS $m\n"; }
function acct(string $status, array $meta, ?string $subStatus = null): HostingAccount {
    $a = new HostingAccount(['status' => $status, 'meta' => $meta]);
    $a->setRelation('subscription', $subStatus ? new ClientSubscription(['status' => $subStatus]) : null);
    return $a;
}
$GB = 1073741824;
ok(acct('active', [], 'active')->suspensionReason() === null, 'active account has no suspension reason');
ok(acct('suspended', ['bw_used_bytes' => 4448420887, 'bw_limit_bytes' => 4294967296], 'active')->suspensionReason() === 'bandwidth', 'usage over the limit -> bandwidth (amkirenga case)');
ok(acct('suspended', ['bw_used_bytes' => 4294967296, 'bw_limit_bytes' => 4294967296], 'active')->suspensionReason() === 'bandwidth', 'usage exactly at the limit -> bandwidth');
ok(acct('suspended', ['bw_used_bytes' => 1 * $GB, 'bw_limit_bytes' => 4 * $GB], 'suspended')->suspensionReason() === 'billing', 'under limit + suspended subscription -> billing');
ok(acct('suspended', ['bw_used_bytes' => 1 * $GB, 'bw_limit_bytes' => 4 * $GB], 'active')->suspensionReason() === 'other', 'under limit + active subscription -> other (not blamed on invoices)');
ok(acct('suspended', [], null)->suspensionReason() === 'other', 'no data -> other');
ok(acct('suspended', ['bw_used_bytes' => 9 * $GB, 'bw_limit_bytes' => 0], 'suspended')->suspensionReason() === 'billing', 'unlimited plan (limit 0) never counts as bandwidth');
echo $fail ? "FAILED $fail\n" : "ALL PASSED\n";
