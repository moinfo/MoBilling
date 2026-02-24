<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('platform_settings', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('key')->unique();
            $table->text('value')->nullable();
            $table->timestamps();
        });

        // Seed default bank details
        $defaults = [
            'platform_bank_name' => 'CRDB Bank',
            'platform_bank_account_name' => 'Moinfotech Company Ltd',
            'platform_bank_account_number' => '0152XXXXXXXX',
            'platform_bank_branch' => 'Dar es Salaam',
            'platform_payment_instructions' => 'Please include your invoice number as payment reference',
        ];

        foreach ($defaults as $key => $value) {
            DB::table('platform_settings')->insert([
                'id' => Str::uuid()->toString(),
                'key' => $key,
                'value' => $value,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('platform_settings');
    }
};
