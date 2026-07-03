<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * WHMCS import support (docs/IMPLEMENTATION_PLAN.md §C0):
     * - legacy_id: the source WHMCS integer id, for idempotent re-runs and
     *   post-import reconciliation.
     * - clients.status / clients.notes: WHMCS client parity fields.
     */
    private array $legacyTables = [
        'clients', 'client_users', 'product_services',
        'client_subscriptions', 'documents', 'payments_in',
    ];

    public function up(): void
    {
        foreach ($this->legacyTables as $table) {
            Schema::table($table, function (Blueprint $t) {
                $t->unsignedBigInteger('legacy_id')->nullable()->index();
            });
        }

        Schema::table('clients', function (Blueprint $t) {
            $t->string('status', 20)->default('active');
            $t->text('notes')->nullable();
        });
    }

    public function down(): void
    {
        foreach ($this->legacyTables as $table) {
            Schema::table($table, function (Blueprint $t) {
                $t->dropColumn('legacy_id');
            });
        }

        Schema::table('clients', function (Blueprint $t) {
            $t->dropColumn(['status', 'notes']);
        });
    }
};
