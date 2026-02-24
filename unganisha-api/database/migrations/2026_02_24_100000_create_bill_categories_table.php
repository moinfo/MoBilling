<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('bill_categories', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('parent_id')->nullable()->constrained('bill_categories')->cascadeOnDelete();
            $table->string('name');
            $table->enum('billing_cycle', ['once', 'monthly', 'quarterly', 'half_yearly', 'yearly'])->nullable();
            $table->boolean('is_active')->default(true);
            $table->timestamps();
            $table->softDeletes();

            $table->index(['tenant_id', 'parent_id']);
        });

        Schema::table('bills', function (Blueprint $table) {
            $table->foreignUuid('bill_category_id')->nullable()->after('category')
                ->constrained('bill_categories')->nullOnDelete();
            $table->date('issue_date')->nullable()->after('name');
        });
    }

    public function down(): void
    {
        Schema::table('bills', function (Blueprint $table) {
            $table->dropConstrainedForeignId('bill_category_id');
            $table->dropColumn('issue_date');
        });

        Schema::dropIfExists('bill_categories');
    }
};
