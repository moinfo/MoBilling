<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // The collection dashboard filters invoices by (tenant, type, due_date)
        // and sorts by due_date; this composite covers those scans.
        Schema::table('documents', function (Blueprint $table) {
            $table->index(['tenant_id', 'type', 'due_date'], 'documents_tenant_type_due_idx');
        });

        // Payment summaries filter by tenant + payment_date (today / month ranges).
        Schema::table('payments_in', function (Blueprint $table) {
            $table->index(['tenant_id', 'payment_date'], 'payments_in_tenant_date_idx');
        });
    }

    public function down(): void
    {
        Schema::table('documents', function (Blueprint $table) {
            $table->dropIndex('documents_tenant_type_due_idx');
        });

        Schema::table('payments_in', function (Blueprint $table) {
            $table->dropIndex('payments_in_tenant_date_idx');
        });
    }
};
