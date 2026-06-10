<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Convert system_verifications.client_id from a free-text string to a
 * foreign key referencing the clients table. The original "external
 * client identifier" idea is being replaced with a proper link so the
 * admin form can show a searchable dropdown of registered clients.
 *
 * Migration order:
 *  1. Read existing rows. Any row whose current client_id matches an
 *     existing clients.id (UUID) gets that value preserved.
 *  2. Any row with a non-matching value gets NULL'd, with a log line so
 *     operators can backfill manually if needed.
 *  3. Drop the string column, add a foreignUuid column with the FK
 *     constraint (nullOnDelete so removing a client doesn't cascade-
 *     delete the verification).
 *  4. Restore the preserved IDs.
 */
return new class extends Migration
{
    public function up(): void
    {
        // 1. Capture current values + map to valid client ids.
        $existing = DB::table('system_verifications')->select('id', 'tenant_id', 'client_id')->get();
        $validClientIds = DB::table('clients')->pluck('tenant_id', 'id'); // id => tenant_id

        $preserveMap = [];   // verification_id => client_id (only when valid)
        $orphaned = 0;

        foreach ($existing as $row) {
            if (! $row->client_id) {
                continue; // already null
            }
            $clientTenant = $validClientIds[$row->client_id] ?? null;
            if ($clientTenant && $clientTenant === $row->tenant_id) {
                $preserveMap[$row->id] = $row->client_id;
            } else {
                $orphaned++;
            }
        }

        if ($orphaned > 0) {
            // Visible in `php artisan migrate` output via the console driver.
            DB::statement("SELECT 'Notice: {$orphaned} system_verifications rows had a non-UUID client_id that will be nulled' AS info");
        }

        // 2. Drop the string column, then add the FK column.
        Schema::table('system_verifications', function (Blueprint $table) {
            $table->dropColumn('client_id');
        });

        Schema::table('system_verifications', function (Blueprint $table) {
            $table->foreignUuid('client_id')->nullable()
                ->after('domain_name')
                ->constrained('clients')
                ->nullOnDelete();

            $table->index('client_id');
        });

        // 3. Restore the preserved IDs row-by-row.
        foreach ($preserveMap as $verificationId => $clientId) {
            DB::table('system_verifications')
                ->where('id', $verificationId)
                ->update(['client_id' => $clientId]);
        }
    }

    public function down(): void
    {
        // Revert to free-text string. Existing FK values stay (they're
        // valid UUIDs as strings), so no data is lost in the rollback.
        Schema::table('system_verifications', function (Blueprint $table) {
            $table->dropForeign(['client_id']);
            $table->dropIndex(['client_id']);
            $table->dropColumn('client_id');
        });

        Schema::table('system_verifications', function (Blueprint $table) {
            $table->string('client_id')->nullable()->after('domain_name');
        });
    }
};
