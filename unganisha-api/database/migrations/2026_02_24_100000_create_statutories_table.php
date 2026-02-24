<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('statutories', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('name');
            $table->foreignUuid('bill_category_id')->nullable()->constrained()->nullOnDelete();
            $table->decimal('amount', 12, 2);
            $table->enum('cycle', ['once', 'monthly', 'quarterly', 'half_yearly', 'yearly']);
            $table->date('issue_date');
            $table->date('next_due_date');
            $table->integer('remind_days_before')->default(3);
            $table->boolean('is_active')->default(true);
            $table->text('notes')->nullable();
            $table->timestamps();
            $table->softDeletes();

            $table->index(['tenant_id', 'is_active', 'next_due_date']);
        });

        Schema::table('bills', function (Blueprint $table) {
            $table->foreignUuid('statutory_id')->nullable()->after('tenant_id')
                ->constrained('statutories')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('bills', function (Blueprint $table) {
            $table->dropForeign(['statutory_id']);
            $table->dropColumn('statutory_id');
        });

        Schema::dropIfExists('statutories');
    }
};
