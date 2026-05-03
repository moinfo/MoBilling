<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Drop unique index so we can clean up data first
        Schema::table('served_customers', function (Blueprint $table) {
            $table->dropUnique('served_customers_phone_date_unique');
        });

        // Normalize all existing phone numbers:
        // Strip non-digits, then strip country code 255/254 → local 0XXXXXXXXX
        $customers = DB::table('served_customers')->whereNotNull('phone')->get();
        foreach ($customers as $c) {
            $normalized = $this->normalize($c->phone);
            if ($normalized !== $c->phone) {
                DB::table('served_customers')->where('id', $c->id)->update(['phone' => $normalized]);
            }
        }

        // Remove duplicates created by normalization (keep oldest)
        DB::statement("
            DELETE sc1 FROM served_customers sc1
            INNER JOIN served_customers sc2
            ON  sc1.tenant_id   = sc2.tenant_id
            AND sc1.phone       = sc2.phone
            AND sc1.served_date = sc2.served_date
            AND sc1.created_at  > sc2.created_at
            WHERE sc1.phone IS NOT NULL
        ");

        // Recreate unique index on normalized data
        Schema::table('served_customers', function (Blueprint $table) {
            $table->unique(['tenant_id', 'phone', 'served_date'], 'served_customers_phone_date_unique');
        });
    }

    public function down(): void {}

    private function normalize(?string $phone): ?string
    {
        if (!$phone) return null;
        $digits = preg_replace('/\D/', '', $phone);
        if (preg_match('/^(255|254)(\d{9})$/', $digits, $m)) {
            return '0' . $m[2];
        }
        return $digits ?: null;
    }
};
