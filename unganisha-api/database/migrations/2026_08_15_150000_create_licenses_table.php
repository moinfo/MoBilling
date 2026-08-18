<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Foundation for selling MoBilling as self-hosted software (WHMCS-style
 * licensing): a self-hosted install periodically calls POST /api/license/
 * validate with its license key + domain; this table is the source of
 * truth for whether that install stays unlocked. Not tenant-scoped — this
 * is MoBilling's own business data (who we sold a license to), not a
 * SaaS tenant's data, so it's managed exclusively via the super-admin
 * panel (Admin\LicenseController), same as SmsPackage/SubscriptionPlan.
 *
 * Domain-locked, single-activation for v1: `domain` starts null and binds
 * itself to whichever domain first successfully validates — after that,
 * a different domain calling with the same key is rejected. Simpler than
 * a multi-activation/seat model; can be extended later if needed.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('licenses', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('license_key')->unique();
            $table->string('customer_name');
            $table->string('customer_email');
            $table->string('product')->default('mobilling-selfhosted');
            $table->string('domain')->nullable();
            $table->enum('status', ['active', 'suspended', 'expired'])->default('active');
            $table->date('expires_at')->nullable();
            $table->timestamp('last_validated_at')->nullable();
            $table->text('notes')->nullable();
            $table->timestamps();
        });

        Schema::create('license_activations', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('license_id')->constrained()->cascadeOnDelete();
            $table->string('domain');
            $table->string('ip_address')->nullable();
            $table->string('app_version')->nullable();
            $table->timestamp('last_seen_at');
            $table->timestamps();

            $table->unique(['license_id', 'domain']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('license_activations');
        Schema::dropIfExists('licenses');
    }
};
