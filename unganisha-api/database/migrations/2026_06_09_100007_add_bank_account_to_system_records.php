<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Optional bank account tag on a System Record. NULL means cash or
     * unspecified channel. nullOnDelete preserves the record if the bank
     * account is later removed; the FK just stops pointing anywhere.
     */
    public function up(): void
    {
        Schema::table('system_records', function (Blueprint $table) {
            $table->foreignUuid('bank_account_id')->nullable()
                ->after('system_property_id')
                ->constrained('bank_accounts')->nullOnDelete();

            $table->index('bank_account_id');
        });
    }

    public function down(): void
    {
        Schema::table('system_records', function (Blueprint $table) {
            $table->dropForeign(['bank_account_id']);
            $table->dropIndex(['bank_account_id']);
            $table->dropColumn('bank_account_id');
        });
    }
};
