<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Document numbers are sequenced per tenant (see DocumentNumberService), so the
     * uniqueness guarantee must be scoped per tenant too. A global unique on
     * document_number alone would make two tenants' "INV-2026-0001" collide.
     */
    public function up(): void
    {
        Schema::table('documents', function (Blueprint $table) {
            $table->dropUnique(['document_number']);
            $table->unique(['tenant_id', 'document_number']);
        });
    }

    public function down(): void
    {
        Schema::table('documents', function (Blueprint $table) {
            $table->dropUnique(['tenant_id', 'document_number']);
            $table->unique(['document_number']);
        });
    }
};
