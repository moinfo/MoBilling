<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * The petty cash seeder (2026_06_02_100004) granted petty_cash.topup and
 * petty_cash.reconcile to every existing role across every tenant. That's
 * too permissive for an accounting feature: "money in" (top-up) and
 * "audit the till" (reconcile) are admin-only actions.
 *
 * This migration revokes both permissions from every role that is not
 * named 'admin'. petty_cash.read and menu.petty_cash stay open so non-admin
 * users can still see the balance for context, and they keep spending
 * through expenses.create (the petty-cash linkage on an expense doesn't
 * require any petty_cash.* permission).
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::statement("
            DELETE rp
            FROM role_permissions rp
            INNER JOIN permissions p ON p.id = rp.permission_id
            INNER JOIN roles r ON r.id = rp.role_id
            WHERE p.name IN ('petty_cash.topup', 'petty_cash.reconcile')
              AND r.name <> 'admin'
        ");
    }

    public function down(): void
    {
        // Re-granting to every role would replicate the original over-permissive
        // seed. Intentionally a no-op — if you want to broaden access again,
        // do it deliberately through the Roles management UI.
    }
};
