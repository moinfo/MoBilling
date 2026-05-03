<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('served_customers', function (Blueprint $table) {
            $table->foreignUuid('created_by_user_id')->nullable()->after('notes')
                ->constrained('users')->nullOnDelete();
        });

        Schema::table('served_customer_feedbacks', function (Blueprint $table) {
            $table->foreignUuid('created_by_user_id')->nullable()->after('internal_notes')
                ->constrained('users')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('served_customers', function (Blueprint $table) {
            $table->dropForeign(['created_by_user_id']);
            $table->dropColumn('created_by_user_id');
        });

        Schema::table('served_customer_feedbacks', function (Blueprint $table) {
            $table->dropForeign(['created_by_user_id']);
            $table->dropColumn('created_by_user_id');
        });
    }
};
