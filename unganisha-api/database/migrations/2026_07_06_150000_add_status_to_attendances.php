<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Excused-day status for attendance: leave (ruhusa), sick (mgonjwa) or
 * field duty (kazi za nje). An excused day is never counted as absent/late
 * and is skipped by the deductions command. NULL = a normal working day.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('attendances', function (Blueprint $table) {
            $table->string('status')->nullable()->after('date'); // leave|sick|field, NULL = normal
            $table->string('status_note')->nullable()->after('status');
        });
    }

    public function down(): void
    {
        Schema::table('attendances', function (Blueprint $table) {
            $table->dropColumn(['status', 'status_note']);
        });
    }
};
