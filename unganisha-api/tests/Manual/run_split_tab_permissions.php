<?php
// php tests/Manual/run_split_tab_permissions.php  (live DB, rolled back at the end)
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\DB;

$fail = 0;
function ok($c, $m) { global $fail; if (!$c) { $fail++; echo "FAIL $m\n"; } else echo "PASS $m\n"; }

$migration = require __DIR__ . '/../../database/migrations/2026_10_06_100000_split_attendance_and_staff_report_tab_permissions.php';

DB::beginTransaction();
try {
    $idOf = fn (string $n) => DB::table('permissions')->where('name', $n)->value('id');
    $holders = fn (string $perm, string $table = 'role_permissions') => DB::table($table)
        ->where('permission_id', $idOf($perm))->pluck($table === 'role_permissions' ? 'role_id' : 'tenant_id')->all();

    // Snapshot who holds the old umbrella permissions BEFORE the migration runs.
    $attManageRoles = DB::table('role_permissions')->where('permission_id', $idOf('attendance.manage'))->pluck('role_id')->all();
    $reviewRoles = DB::table('role_permissions')->where('permission_id', $idOf('staff_reports.review'))->pluck('role_id')->all();
    $submitRoles = DB::table('role_permissions')->where('permission_id', $idOf('staff_reports.submit'))->pluck('role_id')->all();
    $allRoles = DB::table('roles')->pluck('id')->all();

    $migration->up();

    foreach (['attendance.dashboard','attendance.record','attendance.report','attendance.deductions','attendance.requests',
              'attendance.import','attendance.device','attendance.settings','attendance.checkin','attendance.request',
              'staff_reports.dashboard','staff_reports.report','staff_reports.deductions','staff_reports.settings','leave.request'] as $n) {
        ok($idOf($n) !== null, "permission row exists: $n");
    }

    $granted = fn (string $perm) => DB::table('role_permissions')->where('permission_id', $idOf($perm))->pluck('role_id')->all();
    $sameSet = fn (array $a, array $b) => !array_diff($a, $b) && !array_diff($b, $a);

    ok(!empty($attManageRoles) && $sameSet($granted('attendance.record'), $attManageRoles),
       'attendance.record granted to exactly the roles that had attendance.manage');
    ok($sameSet($granted('attendance.settings'), array_values(array_unique(array_merge($attManageRoles, $reviewRoles)))),
       'attendance.settings granted to attendance.manage ∪ staff_reports.review holders');
    ok($sameSet($granted('staff_reports.report'), $reviewRoles), 'staff_reports.report granted to review holders');
    ok($sameSet($granted('staff_reports.dashboard'), $submitRoles), 'staff_reports.dashboard granted to submit holders');
    ok($sameSet($granted('attendance.checkin'), $allRoles), 'self-service attendance.checkin granted to every role');
    ok($sameSet($granted('leave.request'), $allRoles), 'leave.request granted to every role');

    // Tenant + plan layers mirror the role layer for the copied permissions.
    $tenantAtt = DB::table('tenant_permissions')->where('permission_id', $idOf('attendance.manage'))->pluck('tenant_id')->all();
    $tenantRecord = DB::table('tenant_permissions')->where('permission_id', $idOf('attendance.record'))->pluck('tenant_id')->all();
    ok(!array_diff($tenantAtt, $tenantRecord), 'tenant layer: attendance.record covers every tenant with attendance.manage');
    $planAtt = DB::table('subscription_plan_permissions')->where('permission_id', $idOf('attendance.manage'))->pluck('subscription_plan_id')->all();
    $planRecord = DB::table('subscription_plan_permissions')->where('permission_id', $idOf('attendance.record'))->pluck('subscription_plan_id')->all();
    ok(!array_diff($planAtt, $planRecord), 'plan layer: attendance.record covers every plan with attendance.manage');

    // Idempotent: a second run must not duplicate grants.
    $before = DB::table('role_permissions')->where('permission_id', $idOf('attendance.record'))->count();
    $migration->up();
    $after = DB::table('role_permissions')->where('permission_id', $idOf('attendance.record'))->count();
    ok($before === $after, "re-running up() does not duplicate grants ($before -> $after)");

    echo $fail === 0 ? "\nALL PASS\n" : "\n{$fail} FAILURE(S)\n";
} finally {
    DB::rollBack();
    echo "Rolled back — no permanent changes.\n";
}
