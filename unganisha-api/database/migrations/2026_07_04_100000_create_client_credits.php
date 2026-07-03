<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Client credit wallet: append-only ledger + cached balance on clients.
     * (WHMCS parity: tblclients.credit / tblcredit.)
     */
    public function up(): void
    {
        Schema::table('clients', function (Blueprint $t) {
            $t->decimal('credit_balance', 14, 2)->default(0);
        });

        Schema::create('client_credits', function (Blueprint $t) {
            $t->uuid('id')->primary();
            $t->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $t->foreignUuid('client_id')->constrained()->cascadeOnDelete();
            $t->string('type');                       // deposit|apply|adjustment|topup_pending
            $t->decimal('amount', 14, 2);             // signed: + adds credit, - spends it
            $t->decimal('balance_after', 14, 2)->nullable();
            $t->foreignUuid('document_id')->nullable()->constrained()->nullOnDelete();
            $t->foreignUuid('created_by')->nullable()->constrained('users')->nullOnDelete();
            $t->string('notes')->nullable();
            $t->timestamps();
            $t->index(['client_id', 'created_at']);
            $t->index(['type', 'document_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('client_credits');
        Schema::table('clients', function (Blueprint $t) {
            $t->dropColumn('credit_balance');
        });
    }
};
