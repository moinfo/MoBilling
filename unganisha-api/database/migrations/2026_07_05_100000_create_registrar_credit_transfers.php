<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('registrar_credit_transfers', function (Blueprint $table) {
            $table->uuid('id')->primary();
            // platform registrar account (nullable tenant, like registrar_accounts)
            $table->foreignUuid('registrar_account_id')->nullable();
            $table->string('from_zone', 30);
            $table->string('to_zone', 30);
            $table->decimal('amount', 15, 2);
            // pending until TZNIC actions it at the registry, then confirmed by staff
            $table->string('status', 20)->default('pending'); // pending|completed|cancelled
            $table->string('reference')->nullable();
            $table->text('notes')->nullable();
            $table->foreignUuid('requested_by')->nullable();
            $table->string('requested_by_name')->nullable();
            $table->timestamp('completed_at')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('registrar_credit_transfers');
    }
};
