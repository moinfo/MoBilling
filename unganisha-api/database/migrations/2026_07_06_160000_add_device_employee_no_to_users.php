<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Links a staff member to the employee number their HIKVISION attendance
 * terminal reports, so captured device events can be resolved to a user
 * and folded into attendance. NULL = not linked to the device.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('device_employee_no')->nullable()->after('supervisor_id');
            $table->index(['tenant_id', 'device_employee_no']);
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropIndex(['tenant_id', 'device_employee_no']);
            $table->dropColumn('device_employee_no');
        });
    }
};
