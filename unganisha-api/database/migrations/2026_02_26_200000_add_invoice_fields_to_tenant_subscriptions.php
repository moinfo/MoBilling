<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tenant_subscriptions', function (Blueprint $table) {
            $table->string('invoice_number')->nullable()->unique()->after('gateway_response');
            $table->enum('payment_method', ['pesapal', 'bank_transfer'])->nullable()->after('invoice_number');
            $table->string('payment_reference')->nullable()->after('payment_method');
            $table->timestamp('payment_confirmed_at')->nullable()->after('payment_reference');
            $table->foreignUuid('payment_confirmed_by')->nullable()->constrained('users')->nullOnDelete()->after('payment_confirmed_at');
            $table->date('invoice_due_date')->nullable()->after('payment_confirmed_by');
            $table->string('payment_proof_path')->nullable()->after('invoice_due_date');
        });
    }

    public function down(): void
    {
        Schema::table('tenant_subscriptions', function (Blueprint $table) {
            $table->dropForeign(['payment_confirmed_by']);
            $table->dropColumn([
                'invoice_number',
                'payment_method',
                'payment_reference',
                'payment_confirmed_at',
                'payment_confirmed_by',
                'invoice_due_date',
                'payment_proof_path',
            ]);
        });
    }
};
