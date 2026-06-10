<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * The admin-side CRUD on system verifications (register systems, assign
 * staff, view all reports) belongs to the admin role only. Staff still get
 * menu.my_verifications + system_verification_reports.submit so they can
 * see their assigned systems and submit daily check-ins.
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
                'menu.system_verifications',
                'system_verifications.read', 'system_verifications.create',
                'system_verifications.update', 'system_verifications.delete',
                'system_verification_reports.read'
            )
              AND r.name <> 'admin'
        ");
    }

    public function down(): void
    {
        // No-op — re-granting would replicate the open-by-default seed.
    }
};
