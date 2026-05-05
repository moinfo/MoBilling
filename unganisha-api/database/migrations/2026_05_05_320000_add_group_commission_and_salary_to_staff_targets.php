<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('staff_targets', function (Blueprint $table) {
            // Group bonus: fires only when ALL criteria goals are met
            $table->enum('group_commission_type', ['none', 'fixed', 'percentage'])->default('none')->after('supervisor_notes');
            $table->decimal('group_commission_value', 15, 2)->nullable()->after('group_commission_type');
            $table->decimal('group_commission_earned', 15, 2)->nullable()->after('group_commission_value');

            // Salary & failure penalty
            $table->decimal('staff_salary', 15, 2)->nullable()->after('group_commission_earned');
            $table->boolean('deduct_on_failure')->default(false)->after('staff_salary');
            $table->decimal('salary_deduction_earned', 15, 2)->nullable()->after('deduct_on_failure');
        });
    }

    public function down(): void
    {
        Schema::table('staff_targets', function (Blueprint $table) {
            $table->dropColumn([
                'group_commission_type', 'group_commission_value', 'group_commission_earned',
                'staff_salary', 'deduct_on_failure', 'salary_deduction_earned',
            ]);
        });
    }
};