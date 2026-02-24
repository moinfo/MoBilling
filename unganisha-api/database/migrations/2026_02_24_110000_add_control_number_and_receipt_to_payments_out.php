<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('payments_out', function (Blueprint $table) {
            $table->string('control_number')->nullable()->after('payment_method');
            $table->string('receipt_path')->nullable()->after('notes');
        });
    }

    public function down(): void
    {
        Schema::table('payments_out', function (Blueprint $table) {
            $table->dropColumn(['control_number', 'receipt_path']);
        });
    }
};
