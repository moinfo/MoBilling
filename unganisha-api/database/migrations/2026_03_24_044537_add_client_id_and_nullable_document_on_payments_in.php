<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('payments_in', function (Blueprint $table) {
            $table->foreignUuid('client_id')->nullable()->after('document_id')->constrained()->nullOnDelete();
        });

        Schema::table('payments_in', function (Blueprint $table) {
            $table->dropForeign(['document_id']);
            $table->uuid('document_id')->nullable()->change();
            $table->foreign('document_id')->references('id')->on('documents')->nullOnDelete();
        });

        // Backfill client_id from existing document relationships
        DB::statement('
            UPDATE payments_in p
            JOIN documents d ON d.id = p.document_id
            SET p.client_id = d.client_id
            WHERE p.client_id IS NULL
        ');
    }

    public function down(): void
    {
        Schema::table('payments_in', function (Blueprint $table) {
            $table->dropForeign(['client_id']);
            $table->dropColumn('client_id');
        });

        Schema::table('payments_in', function (Blueprint $table) {
            $table->dropForeign(['document_id']);
            $table->uuid('document_id')->nullable(false)->change();
            $table->foreign('document_id')->references('id')->on('documents')->cascadeOnDelete();
        });
    }
};