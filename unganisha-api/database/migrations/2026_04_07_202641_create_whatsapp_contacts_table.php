<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('whatsapp_contacts', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();

            $table->string('name');
            $table->string('phone');
            $table->enum('label', [
                'lead',
                'new_customer',
                'new_order',
                'follow_up',
                'pending_payment',
                'paid',
                'order_complete',
            ])->default('lead');
            $table->boolean('is_important')->default(false);
            $table->enum('source', ['whatsapp_ad', 'direct', 'referral', 'other'])->default('whatsapp_ad');
            $table->string('ad_campaign')->nullable();
            $table->text('notes')->nullable();
            $table->date('next_followup_date')->nullable();
            $table->foreignUuid('assigned_to')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignUuid('client_id')->nullable()->constrained('clients')->nullOnDelete();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('whatsapp_contacts');
    }
};
