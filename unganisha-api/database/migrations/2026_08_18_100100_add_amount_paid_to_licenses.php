<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/** Records what was actually charged for a license — defaults to the license_plans catalog price at issue time, but editable (discounts, custom deals). */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('licenses', function (Blueprint $table) {
            $table->decimal('amount_paid', 12, 2)->nullable()->after('billing_period');
        });
    }

    public function down(): void
    {
        Schema::table('licenses', function (Blueprint $table) {
            $table->dropColumn('amount_paid');
        });
    }
};
