<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * v1 simplification: recovered as a single lump sum in one designated
 * month, not split across several payroll periods like a Loan.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('salary_advances', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('user_id')->constrained()->cascadeOnDelete();
            $table->decimal('amount', 12, 2);
            $table->date('issued_date');
            $table->string('recovery_month_key');
            $table->enum('status', ['pending', 'recovered', 'cancelled'])->default('pending');
            $table->text('notes')->nullable();
            $table->foreignUuid('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->index(['tenant_id', 'user_id', 'recovery_month_key']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('salary_advances');
    }
};
