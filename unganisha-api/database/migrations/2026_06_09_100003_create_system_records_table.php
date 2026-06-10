<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('system_records', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('system_id')->constrained('systems')->cascadeOnDelete();
            $table->foreignUuid('system_property_id')->constrained('system_properties')->cascadeOnDelete();
            $table->foreignUuid('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->date('record_date');
            $table->decimal('amount', 14, 2);
            $table->text('notes')->nullable();
            $table->timestamps();
            $table->softDeletes();

            $table->index(['tenant_id', 'record_date']);
            $table->index('system_id');
            $table->index('system_property_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('system_records');
    }
};
