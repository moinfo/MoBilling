<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Remove obvious duplicate rows before adding constraint
        \Illuminate\Support\Facades\DB::statement("
            DELETE sc1 FROM served_customers sc1
            INNER JOIN served_customers sc2
            ON  sc1.tenant_id   = sc2.tenant_id
            AND sc1.phone       = sc2.phone
            AND sc1.served_date = sc2.served_date
            AND sc1.created_at  > sc2.created_at
            WHERE sc1.phone IS NOT NULL
        ");

        Schema::table('served_customers', function (Blueprint $table) {
            // Unique per tenant: same phone cannot appear twice on the same date
            $table->unique(['tenant_id', 'phone', 'served_date'], 'served_customers_phone_date_unique');
        });
    }

    public function down(): void
    {
        Schema::table('served_customers', function (Blueprint $table) {
            $table->dropUnique('served_customers_phone_date_unique');
        });
    }
};
