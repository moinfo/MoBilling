<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('wifi_voucher_purchases', function (Blueprint $table) {
            $table->timestamp('blocked_at')->nullable()->after('voucher_expires_at');
            $table->string('blocked_reason')->nullable()->after('blocked_at');
            $table->foreignUuid('blocked_by')->nullable()->after('blocked_reason')->constrained('users')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('wifi_voucher_purchases', function (Blueprint $table) {
            $table->dropForeign(['blocked_by']);
            $table->dropColumn(['blocked_at', 'blocked_reason', 'blocked_by']);
        });
    }
};
