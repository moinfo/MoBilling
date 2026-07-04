<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * Credit notes reuse the documents + document_items tables (like invoices),
     * so the type enum is widened additively to include 'credit_note'. They get
     * their own CN- number series via DocumentNumberService.
     */
    public function up(): void
    {
        DB::statement("ALTER TABLE documents MODIFY COLUMN type ENUM('quotation','proforma','invoice','credit_note')");
    }

    public function down(): void
    {
        // Return any credit notes to a benign value before narrowing the enum,
        // otherwise the MODIFY would fail / coerce them.
        DB::table('documents')->where('type', 'credit_note')->update(['type' => 'invoice']);

        DB::statement("ALTER TABLE documents MODIFY COLUMN type ENUM('quotation','proforma','invoice')");
    }
};
