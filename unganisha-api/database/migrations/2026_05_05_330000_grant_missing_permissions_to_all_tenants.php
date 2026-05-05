<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Several recent feature migrations (WhatsApp, Field Marketing, Social Media,
 * Served Customers, Marketing Services, Staff Reports, Staff Targets) added
 * permissions to the permissions table but forgot to grant them to existing
 * tenants via tenant_permissions. This migration finds every permission that is
 * missing for every tenant and inserts the gaps.
 */
return new class extends Migration
{
    public function up(): void
    {
        $tenantIds = DB::table('tenants')->pluck('id');
        $allPermIds = DB::table('permissions')->pluck('id');

        foreach ($tenantIds as $tenantId) {
            $existing = DB::table('tenant_permissions')
                ->where('tenant_id', $tenantId)
                ->pluck('permission_id')
                ->flip();

            $inserts = $allPermIds
                ->reject(fn ($pid) => isset($existing[$pid]))
                ->map(fn ($pid) => [
                    'tenant_id'     => $tenantId,
                    'permission_id' => $pid,
                ])
                ->values()
                ->all();

            if (!empty($inserts)) {
                DB::table('tenant_permissions')->insertOrIgnore($inserts);
            }
        }
    }

    public function down(): void
    {
        // Irreversible: we can't know which entries were missing before
    }
};
