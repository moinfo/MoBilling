<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * A configured option attached to a live service. label/unit_price/quantity/
     * billing_cycle are snapshots taken at activation so later catalog edits
     * don't change what an existing service is billed on renewals.
     */
    public function up(): void
    {
        Schema::create('subscription_config_options', function (Blueprint $t) {
            $t->uuid('id')->primary();
            $t->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $t->foreignUuid('client_subscription_id')->constrained()->cascadeOnDelete();
            $t->foreignUuid('config_option_id')->nullable()->constrained()->nullOnDelete();
            $t->foreignUuid('choice_id')->nullable()->constrained('config_option_choices')->nullOnDelete();
            $t->string('label'); // snapshot e.g. "RAM: 8GB" or "Extra Mailboxes x5"
            $t->decimal('unit_price', 15, 2)->default(0);
            $t->integer('quantity')->default(1);
            $t->enum('billing_cycle', ['once', 'monthly', 'quarterly', 'half_yearly', 'yearly'])->default('monthly');
            $t->decimal('tax_percent', 5, 2)->default(0);
            $t->enum('status', ['active', 'cancelled'])->default('active');
            $t->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('subscription_config_options');
    }
};
