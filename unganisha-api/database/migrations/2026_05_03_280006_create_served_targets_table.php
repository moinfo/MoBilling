<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('served_targets', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->unsignedSmallInteger('new_customers_target')->default(10);
            $table->unsignedSmallInteger('called_customers_target')->default(5);
            $table->json('active_days');   // ISO weekdays: 1=Mon … 7=Sun
            $table->date('effective_from');
            $table->timestamps();

            $table->index('tenant_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('served_targets');
    }
};
