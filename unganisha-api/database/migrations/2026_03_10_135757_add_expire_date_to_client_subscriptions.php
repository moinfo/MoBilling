<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('client_subscriptions', function (Blueprint $table) {
            $table->date('expire_date')->nullable()->after('start_date');
        });

        // Backfill expire_date for existing subscriptions based on start_date + billing_cycle
        DB::statement("
            UPDATE client_subscriptions cs
            JOIN product_services ps ON cs.product_service_id = ps.id
            SET cs.expire_date = CASE ps.billing_cycle
                WHEN 'monthly' THEN DATE_ADD(cs.start_date, INTERVAL 1 MONTH)
                WHEN 'quarterly' THEN DATE_ADD(cs.start_date, INTERVAL 3 MONTH)
                WHEN 'half_yearly' THEN DATE_ADD(cs.start_date, INTERVAL 6 MONTH)
                WHEN 'yearly' THEN DATE_ADD(cs.start_date, INTERVAL 1 YEAR)
                ELSE NULL
            END
            WHERE cs.expire_date IS NULL
        ");
    }

    public function down(): void
    {
        Schema::table('client_subscriptions', function (Blueprint $table) {
            $table->dropColumn('expire_date');
        });
    }
};
