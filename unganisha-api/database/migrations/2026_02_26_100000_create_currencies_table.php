<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('currencies', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('code', 10)->unique();   // ISO 4217: KES, USD, TZS
            $table->string('name');                   // Kenya Shilling
            $table->string('symbol', 10)->nullable(); // KSh, $, TSh
            $table->boolean('is_active')->default(true);
            $table->integer('sort_order')->default(0);
            $table->timestamps();
        });

        // Seed common currencies
        $now = now();
        DB::table('currencies')->insert([
            ['id' => \Illuminate\Support\Str::uuid(), 'code' => 'TZS', 'name' => 'Tanzanian Shilling', 'symbol' => 'TSh', 'is_active' => true, 'sort_order' => 0, 'created_at' => $now, 'updated_at' => $now],
            ['id' => \Illuminate\Support\Str::uuid(), 'code' => 'KES', 'name' => 'Kenyan Shilling', 'symbol' => 'KSh', 'is_active' => true, 'sort_order' => 1, 'created_at' => $now, 'updated_at' => $now],
            ['id' => \Illuminate\Support\Str::uuid(), 'code' => 'USD', 'name' => 'US Dollar', 'symbol' => '$', 'is_active' => true, 'sort_order' => 2, 'created_at' => $now, 'updated_at' => $now],
            ['id' => \Illuminate\Support\Str::uuid(), 'code' => 'EUR', 'name' => 'Euro', 'symbol' => '€', 'is_active' => true, 'sort_order' => 3, 'created_at' => $now, 'updated_at' => $now],
            ['id' => \Illuminate\Support\Str::uuid(), 'code' => 'GBP', 'name' => 'British Pound', 'symbol' => '£', 'is_active' => true, 'sort_order' => 4, 'created_at' => $now, 'updated_at' => $now],
            ['id' => \Illuminate\Support\Str::uuid(), 'code' => 'UGX', 'name' => 'Ugandan Shilling', 'symbol' => 'USh', 'is_active' => false, 'sort_order' => 5, 'created_at' => $now, 'updated_at' => $now],
            ['id' => \Illuminate\Support\Str::uuid(), 'code' => 'RWF', 'name' => 'Rwandan Franc', 'symbol' => 'RF', 'is_active' => false, 'sort_order' => 6, 'created_at' => $now, 'updated_at' => $now],
        ]);
    }

    public function down(): void
    {
        Schema::dropIfExists('currencies');
    }
};
