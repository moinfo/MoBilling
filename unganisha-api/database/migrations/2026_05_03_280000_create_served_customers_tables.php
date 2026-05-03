<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('served_services', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('name');
            $table->string('description')->nullable();
            $table->boolean('is_active')->default(true);
            $table->unsignedSmallInteger('sort_order')->default(99);
            $table->timestamps();

            $table->index('tenant_id');
        });

        Schema::create('served_customers', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('name');
            $table->string('phone')->nullable();
            $table->date('served_date');
            $table->text('notes')->nullable();
            $table->timestamps();

            $table->index(['tenant_id', 'served_date']);
        });

        Schema::create('served_customer_service', function (Blueprint $table) {
            $table->foreignUuid('served_customer_id')->constrained('served_customers')->cascadeOnDelete();
            $table->foreignUuid('served_service_id')->constrained('served_services')->cascadeOnDelete();
            $table->primary(['served_customer_id', 'served_service_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('served_customer_service');
        Schema::dropIfExists('served_customers');
        Schema::dropIfExists('served_services');
    }
};
