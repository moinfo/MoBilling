<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Pricing catalog for self-hosted licenses (License model) — a completely
 * separate commercial line from subscription_plans, which prices MoBilling
 * SaaS itself (a tenant paying to use mobilling.co.tz). This prices a
 * customer installing MoBilling on their OWN server, one row per package
 * (lite/reseller/general — same three as License.product /
 * TenantProvisioningService), with a price per billing period so there's
 * no combinatorial row explosion (3 rows total, not 3 x 5).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('license_plans', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->enum('product', ['lite', 'reseller', 'general'])->unique();
            $table->string('name');
            $table->text('description')->nullable();
            $table->decimal('monthly_price', 12, 2)->nullable();
            $table->decimal('quarterly_price', 12, 2)->nullable();
            $table->decimal('semi_annual_price', 12, 2)->nullable();
            $table->decimal('annual_price', 12, 2)->nullable();
            $table->decimal('perpetual_price', 12, 2)->nullable();
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });

        $rows = [
            ['product' => 'lite', 'name' => 'MoBilling Lite', 'description' => 'Billing & CRM basics — no domains or hosting.'],
            ['product' => 'reseller', 'name' => 'MoBilling Reseller', 'description' => 'The WHMCS-style toolkit, including domains & hosting.'],
            ['product' => 'general', 'name' => 'MoBilling Complete', 'description' => 'The full platform — everything.'],
        ];
        foreach ($rows as $row) {
            DB::table('license_plans')->insert(array_merge($row, [
                'id' => (string) Str::uuid(),
                'is_active' => true,
                'created_at' => now(),
                'updated_at' => now(),
            ]));
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('license_plans');
    }
};
