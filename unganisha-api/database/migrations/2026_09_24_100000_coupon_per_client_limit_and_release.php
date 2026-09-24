<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasColumn('coupons', 'max_uses_per_client')) {
            Schema::table('coupons', function (Blueprint $t) {
                $t->unsignedInteger('max_uses_per_client')->nullable()->after('max_uses'); // null = unlimited
            });
        }
        if (!Schema::hasColumn('coupon_redemptions', 'released_at')) {
            Schema::table('coupon_redemptions', function (Blueprint $t) {
                $t->dateTime('released_at')->nullable(); // set when the unpaid order was cancelled
            });
        }
    }

    public function down(): void
    {
        Schema::table('coupons', fn (Blueprint $t) => $t->dropColumn('max_uses_per_client'));
        Schema::table('coupon_redemptions', fn (Blueprint $t) => $t->dropColumn('released_at'));
    }
};
