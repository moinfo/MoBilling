<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Links a self-service "Pay via Lipa Number" wallet top-up to the real invoice
 * (Document) issued under Moinfotech's own tenant so it shows up on the
 * platform's own /invoices list — staff were only seeing these on the
 * reseller's isolated wallet screen, with no way to track/collect them
 * through the normal invoicing workflow they already use every day.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tenant_wallet_topups', function (Blueprint $table) {
            $table->foreignUuid('document_id')->nullable()->after('requested_by')->constrained()->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('tenant_wallet_topups', function (Blueprint $table) {
            $table->dropForeign(['document_id']);
            $table->dropColumn('document_id');
        });
    }
};
