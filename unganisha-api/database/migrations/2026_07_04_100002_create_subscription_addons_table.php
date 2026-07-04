<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * An add-on attached to a live service. name/price/billing_cycle are
     * snapshots taken at activation so later catalog edits don't change what
     * an existing service is billed on renewals.
     */
    public function up(): void
    {
        Schema::create('subscription_addons', function (Blueprint $t) {
            $t->uuid('id')->primary();
            $t->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $t->foreignUuid('client_subscription_id')->constrained()->cascadeOnDelete();
            $t->foreignUuid('product_addon_id')->nullable()->constrained()->nullOnDelete();
            $t->string('name');
            $t->decimal('price', 15, 2)->default(0);
            $t->enum('billing_cycle', ['once', 'monthly', 'quarterly', 'half_yearly', 'yearly'])->default('monthly');
            $t->decimal('tax_percent', 5, 2)->default(0);
            $t->enum('status', ['active', 'cancelled'])->default('active');
            $t->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('subscription_addons');
    }
};
