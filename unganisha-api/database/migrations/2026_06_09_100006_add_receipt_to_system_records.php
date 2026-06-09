<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * A System Record is a financial entry — it must carry proof. The
     * receipt_attachment_path column stores the uploaded scan/PDF.
     *
     * The column is technically nullable so existing rows survive, but
     * the FormRequest enforces required-on-create at the API layer.
     */
    public function up(): void
    {
        Schema::table('system_records', function (Blueprint $table) {
            $table->string('receipt_attachment_path')->nullable()->after('notes');
        });
    }

    public function down(): void
    {
        Schema::table('system_records', function (Blueprint $table) {
            $table->dropColumn('receipt_attachment_path');
        });
    }
};
