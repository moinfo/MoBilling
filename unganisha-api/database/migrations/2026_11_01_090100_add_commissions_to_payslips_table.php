<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('payslips', function (Blueprint $table) {
            $table->decimal('commissions_total', 12, 2)->default(0)->after('allowances_breakdown');
            $table->json('commissions_breakdown')->nullable()->after('commissions_total');
        });
    }

    public function down(): void
    {
        Schema::table('payslips', function (Blueprint $table) {
            $table->dropColumn(['commissions_total', 'commissions_breakdown']);
        });
    }
};
