<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
return new class extends Migration {
    public function up(): void {
        Schema::create('attendance_settings', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->unique()->constrained()->cascadeOnDelete();
            $table->string('check_in_time', 5)->default('07:30');
            $table->string('check_out_time', 5)->default('17:00');
            $table->boolean('penalties_enabled')->default(true);
            $table->decimal('penalty_absent', 12, 2)->default(5000);
            $table->decimal('penalty_late', 12, 2)->default(2000);
            $table->decimal('penalty_left_early', 12, 2)->default(2000);
            $table->decimal('penalty_no_checkout', 12, 2)->default(2000);
            $table->json('working_days')->nullable(); // ISO 1..7, default Mon-Sat
            $table->timestamps();
        });
    }
    public function down(): void { Schema::dropIfExists('attendance_settings'); }
};
