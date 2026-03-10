<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('portal_otps', function (Blueprint $table) {
            $table->dropForeign(['client_id']);
            $table->dropForeign(['tenant_id']);
        });

        Schema::table('portal_otps', function (Blueprint $table) {
            $table->uuid('client_id')->nullable()->change();
            $table->uuid('tenant_id')->nullable()->change();
            $table->foreign('client_id')->references('id')->on('clients')->cascadeOnDelete();
            $table->foreign('tenant_id')->references('id')->on('tenants')->cascadeOnDelete();
        });
    }

    public function down(): void
    {
        // Not reversible cleanly
    }
};
