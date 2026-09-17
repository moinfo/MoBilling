<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->foreignUuid('work_location_id')
                ->nullable()
                ->after('supervisor_id')
                ->constrained('work_locations')
                ->nullOnDelete();

            // Bound on this user's first app self-check-in — every check-in
            // after that must come from the same device, or it's rejected
            // (see AttendanceController::checkIn). An admin clears these
            // three via AttendanceController::resetDevice when a staff
            // member gets a new phone.
            $table->string('attendance_device_id')->nullable();
            // Human-readable make/model ("Samsung SM-A546E", "iPhone15,2")
            // captured at binding time — purely informational, so an admin
            // resetting a binding knows whose phone they're looking at.
            $table->string('attendance_device_model')->nullable();
            $table->timestamp('attendance_device_bound_at')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropForeign(['work_location_id']);
            $table->dropColumn([
                'work_location_id',
                'attendance_device_id',
                'attendance_device_model',
                'attendance_device_bound_at',
            ]);
        });
    }
};
