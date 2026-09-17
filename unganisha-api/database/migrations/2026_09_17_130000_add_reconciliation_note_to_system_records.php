<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /** Lets whoever is reconciling (SMS or statement checker) flag a discrepancy on a record — e.g. "not seen on statement yet". */
    public function up(): void
    {
        Schema::table('system_records', function (Blueprint $table) {
            $table->text('reconciliation_note')->nullable()->after('statement_confirmed_by');
        });
    }

    public function down(): void
    {
        Schema::table('system_records', function (Blueprint $table) {
            $table->dropColumn('reconciliation_note');
        });
    }
};
