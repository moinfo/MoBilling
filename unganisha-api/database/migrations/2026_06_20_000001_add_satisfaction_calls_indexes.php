<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('satisfaction_calls', function (Blueprint $table) {
            // The appointments() endpoint filters/sorts on these (list + 6 stat counts).
            $table->index(['tenant_id', 'appointment_requested', 'appointment_date'], 'satisfaction_appt_idx');
            // History month filter when no client_id is supplied.
            $table->index(['tenant_id', 'month_key'], 'satisfaction_tenant_month_idx');
        });
    }

    public function down(): void
    {
        Schema::table('satisfaction_calls', function (Blueprint $table) {
            $table->dropIndex('satisfaction_appt_idx');
            $table->dropIndex('satisfaction_tenant_month_idx');
        });
    }
};
