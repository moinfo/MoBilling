<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * The original seeder (2026_06_09_100004) granted every new permission to
 * every existing role. That's appropriate for the data-entry CRUD
 * (System Records) but too permissive for the three supporting
 * configuration entities — Systems / Bank Accounts / System Properties
 * are reference data only admins should touch.
 *
 * This migration revokes both the menu visibility AND the four CRUD
 * permissions for those three settings from every role that is not
 * named 'admin'. System Records (read/create/update/delete + menu) is
 * deliberately untouched so any role can keep recording data.
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
            WHERE p.name IN (
                'menu.systems', 'menu.bank_accounts', 'menu.system_properties',
                'systems.read', 'systems.create', 'systems.update', 'systems.delete',
                'bank_accounts.read', 'bank_accounts.create', 'bank_accounts.update', 'bank_accounts.delete',
                'system_properties.read', 'system_properties.create', 'system_properties.update', 'system_properties.delete'
            )
              AND r.name <> 'admin'
        ");
    }

    public function down(): void
    {
        // Re-granting to every role would replicate the original over-permissive
        // seed. Intentionally a no-op — to broaden access again, do it
        // deliberately through the Roles management UI.
    }
};
