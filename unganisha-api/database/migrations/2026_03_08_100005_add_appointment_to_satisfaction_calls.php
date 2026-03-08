<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Add appointment fields to satisfaction_calls for physical visit scheduling.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('satisfaction_calls', function (Blueprint $table) {
            $table->boolean('appointment_requested')->default(false)->after('internal_notes');
            $table->date('appointment_date')->nullable()->after('appointment_requested');
            $table->string('appointment_notes', 500)->nullable()->after('appointment_date');
            $table->enum('appointment_status', ['pending', 'confirmed', 'completed', 'cancelled'])->nullable()->after('appointment_notes');
        });
    }

    public function down(): void
    {
        Schema::table('satisfaction_calls', function (Blueprint $table) {
            $table->dropColumn(['appointment_requested', 'appointment_date', 'appointment_notes', 'appointment_status']);
        });
    }
};
