<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
return new class extends Migration {
    public function up(): void {
        Schema::create('attendance_devices', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('name')->default('HIKVISION device');
            $table->string('token', 64)->unique();
            $table->boolean('is_active')->default(true);
            $table->timestamp('last_event_at')->nullable();
            $table->timestamps();
        });
    }
    public function down(): void { Schema::dropIfExists('attendance_devices'); }
};
