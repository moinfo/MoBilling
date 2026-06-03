<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('petty_cash_accounts', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('name')->default('Petty Cash');
            $table->decimal('opening_balance', 12, 2)->default(0);
            $table->boolean('is_active')->default(true);
            $table->timestamps();
            $table->softDeletes();

            // Single petty cash pool per tenant (the design choice).
            // Future multi-pool support can drop this and the column stays.
            $table->unique('tenant_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('petty_cash_accounts');
    }
};
