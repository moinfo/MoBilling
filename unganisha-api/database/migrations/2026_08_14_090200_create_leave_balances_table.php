<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A per-employee/type/year grant set by HR. Used/remaining days are
 * computed on read from approved+non-cancelled leave_requests, not stored
 * here — avoids a second mutable counter that can drift out of sync with
 * the requests themselves.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('leave_balances', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('user_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('leave_type_id')->constrained()->cascadeOnDelete();
            $table->unsignedSmallInteger('year');
            $table->unsignedSmallInteger('allocated_days')->default(0);
            $table->timestamps();

            $table->unique(['user_id', 'leave_type_id', 'year']);
            $table->index('tenant_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('leave_balances');
    }
};
