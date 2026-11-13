<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * A 4th self-hosted license tier, "MoBilling WiFi Hotspot" — just the
 * voucher-selling module, for someone who wants nothing else. Widens the
 * product enum (MySQL requires a raw MODIFY for this — Laravel has no
 * schema-builder helper to alter an existing enum's allowed values) and
 * seeds the row the same way the original three were seeded, since
 * Admin\LicensePlanController::update() deliberately never creates rows.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::statement("ALTER TABLE license_plans MODIFY product ENUM('lite', 'reseller', 'general', 'wifi_hotspot') NOT NULL");

        DB::table('license_plans')->insert([
            'id' => (string) Str::uuid(),
            'product' => 'wifi_hotspot',
            'name' => 'MoBilling WiFi Hotspot',
            'description' => 'Just the WiFi hotspot voucher-selling module — connect your MikroTik and start selling vouchers.',
            'monthly_price' => 5000,
            'quarterly_price' => 12500,
            'semi_annual_price' => 22500,
            'annual_price' => 40000,
            'is_active' => true,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    public function down(): void
    {
        DB::table('license_plans')->where('product', 'wifi_hotspot')->delete();
        DB::statement("ALTER TABLE license_plans MODIFY product ENUM('lite', 'reseller', 'general') NOT NULL");
    }
};
