<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ad-hoc commission entries, paid out through a designated payroll month —
 * same v1 shape as SalaryAdvance (one lump sum in one month, not split).
 * A pending commission adds to that month's gross pay; finalize() marks it
 * paid so it can never be pulled into a second payroll run.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('commissions', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('user_id')->constrained()->cascadeOnDelete();
            $table->decimal('amount', 12, 2);
            $table->date('earned_date');
            $table->string('payout_month_key');
            $table->enum('status', ['pending', 'paid', 'cancelled'])->default('pending');
            $table->text('notes')->nullable();
            $table->foreignUuid('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->index(['tenant_id', 'user_id', 'payout_month_key']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('commissions');
    }
};
