<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Tracks what a System Records withdrawal was actually spent on — one
     * withdraw can have several expense lines against it (a split spend),
     * each with an optional receipt. Lets staff answer "we withdrew X, here's
     * proof of how it was used" rather than a withdraw record just
     * disappearing with no accountability trail.
     */
    public function up(): void
    {
        Schema::create('system_record_expenses', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('system_record_id')->constrained('system_records')->cascadeOnDelete();
            $table->decimal('amount', 14, 2);
            $table->date('expense_date');
            $table->string('description');
            $table->string('attachment_path')->nullable();
            $table->foreignUuid('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();
            $table->softDeletes();

            $table->index(['tenant_id', 'system_record_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('system_record_expenses');
    }
};
