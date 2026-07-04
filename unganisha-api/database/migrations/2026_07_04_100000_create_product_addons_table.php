<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Paid product add-ons (WHMCS-parity upsell): tenant-defined extras
     * (Dedicated IP, Extra Storage, Daily Backups, SSL, …) attachable to
     * hosting products and billed on the order + recurring renewal invoices.
     */
    public function up(): void
    {
        Schema::create('product_addons', function (Blueprint $t) {
            $t->uuid('id')->primary();
            $t->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $t->string('name');
            $t->text('description')->nullable();
            $t->decimal('price', 15, 2)->default(0);
            $t->enum('billing_cycle', ['once', 'monthly', 'quarterly', 'half_yearly', 'yearly'])->default('monthly');
            $t->decimal('tax_percent', 5, 2)->default(0);
            $t->boolean('is_active')->default(true);
            $t->timestamps();
            $t->softDeletes();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('product_addons');
    }
};
