<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Deposit slip / transaction ID — lets staff catch the same receipt
     * being entered twice. No DB-level unique index (soft-deleted rows
     * would collide with a legitimately re-entered reference); uniqueness
     * is enforced in StoreSystemRecordRequest with ->whereNull('deleted_at'),
     * matching this app's existing convention for scoped uniqueness checks.
     */
    public function up(): void
    {
        Schema::table('system_records', function (Blueprint $table) {
            $table->string('transaction_reference')->nullable()->after('type');
        });
    }

    public function down(): void
    {
        Schema::table('system_records', function (Blueprint $table) {
            $table->dropColumn('transaction_reference');
        });
    }
};
