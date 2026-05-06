<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('staff_targets', function (Blueprint $table) {
            $table->foreignUuid('manager_id')->nullable()
                ->after('salary_deduction_earned')
                ->constrained('users')->nullOnDelete();
            $table->enum('manager_commission_type', ['none', 'fixed', 'percentage'])
                ->default('none')
                ->after('manager_id');
            $table->decimal('manager_commission_value', 15, 2)->nullable()
                ->after('manager_commission_type');
            $table->decimal('manager_commission_earned', 15, 2)->nullable()
                ->after('manager_commission_value');
        });
    }

    public function down(): void
    {
        Schema::table('staff_targets', function (Blueprint $table) {
            $table->dropConstrainedForeignId('manager_id');
            $table->dropColumn(['manager_commission_type', 'manager_commission_value', 'manager_commission_earned']);
        });
    }
};
