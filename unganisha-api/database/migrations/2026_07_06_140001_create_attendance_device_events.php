<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
return new class extends Migration {
    public function up(): void {
        Schema::create('attendance_device_events', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->nullable();
            $table->foreignUuid('attendance_device_id')->nullable();
            $table->string('content_type')->nullable();
            $table->string('employee_no')->nullable();   // best-effort extract
            $table->timestamp('event_time')->nullable();  // best-effort extract
            $table->longText('payload')->nullable();       // raw body (capped)
            $table->json('parsed')->nullable();            // parsed fields / form inputs
            $table->boolean('processed')->default(false);  // used once we wire real import
            $table->timestamps();
            $table->index(['tenant_id', 'created_at']);
        });
    }
    public function down(): void { Schema::dropIfExists('attendance_device_events'); }
};
