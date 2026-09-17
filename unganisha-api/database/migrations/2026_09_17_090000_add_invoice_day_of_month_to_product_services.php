<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * A second, opt-in billing model alongside the existing cycle-based one
     * (billing_cycle + "invoice N days ahead of the renewal date"): some
     * contracts (e.g. a monthly retainer) need a FIXED calendar issue date
     * every month — e.g. always invoice on the 25th — with the due date
     * always the last day of that month (the day before the 1st),
     * regardless of month length. See
     * RecurringInvoiceService::processDayOfMonthBills().
     */
    public function up(): void
    {
        Schema::table('product_services', function (Blueprint $table) {
            $table->unsignedTinyInteger('invoice_day_of_month')->nullable()->after('billing_cycle');
        });
    }

    public function down(): void
    {
        Schema::table('product_services', function (Blueprint $table) {
            $table->dropColumn('invoice_day_of_month');
        });
    }
};
