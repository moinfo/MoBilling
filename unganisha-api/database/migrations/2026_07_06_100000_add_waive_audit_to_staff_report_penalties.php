<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('staff_report_penalties', function (Blueprint $table) {
            $table->foreignUuid('waived_by')->nullable()->after('waived');
            $table->timestamp('waived_at')->nullable()->after('waived_by');
            $table->string('waive_reason')->nullable()->after('waived_at');
        });
    }

    public function down(): void
    {
        Schema::table('staff_report_penalties', function (Blueprint $table) {
            $table->dropColumn(['waived_by', 'waived_at', 'waive_reason']);
        });
    }
};
