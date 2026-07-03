<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Domain registrar integration (docs/DOMAIN_REGISTRAR_INTEGRATION.md §5,
     * docs/IMPLEMENTATION_PLAN.md §B1).
     */
    public function up(): void
    {
        // NULL tenant_id = the platform's registrar accreditation, used as the
        // fallback for every tenant that doesn't hold its own.
        Schema::create('registrar_accounts', function (Blueprint $t) {
            $t->uuid('id')->primary();
            $t->foreignUuid('tenant_id')->nullable()->constrained()->cascadeOnDelete();
            $t->string('name');
            $t->string('driver')->default('fred_epp');
            $t->string('endpoint_url');                 // registrar service base URL
            $t->string('registrar_id')->nullable();     // e.g. REG-MOINFOTECH
            $t->text('credentials');                    // encrypted:array (service token, ...)
            $t->boolean('is_active')->default(true);
            $t->boolean('is_sandbox')->default(false);
            $t->timestamps();
            $t->index(['tenant_id', 'is_active']);
        });

        // Pricing catalog: NULL tenant row = platform base cost; tenant rows
        // override with their retail price.
        Schema::create('domain_tlds', function (Blueprint $t) {
            $t->uuid('id')->primary();
            $t->foreignUuid('tenant_id')->nullable()->constrained()->cascadeOnDelete();
            $t->string('tld');                          // e.g. co.tz
            $t->decimal('register_price', 12, 2);
            $t->decimal('renew_price', 12, 2);
            $t->decimal('transfer_price', 12, 2)->default(0);
            $t->unsignedTinyInteger('years_min')->default(1);
            $t->unsignedTinyInteger('years_max')->default(10);
            $t->boolean('is_active')->default(true);
            $t->timestamps();
            $t->unique(['tenant_id', 'tld']);
        });

        Schema::create('domains', function (Blueprint $t) {
            $t->uuid('id')->primary();
            $t->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $t->foreignUuid('client_id')->constrained()->cascadeOnDelete();
            $t->foreignUuid('registrar_account_id')->nullable()->constrained('registrar_accounts')->nullOnDelete();
            $t->string('name');                         // registry-global unique
            $t->string('status')->default('pending');   // pending|active|expired|transferred_out|cancelled|failed
            $t->string('registrant_handle')->nullable();
            $t->string('admin_handle')->nullable();
            $t->string('nsset_handle')->nullable();
            $t->string('keyset_handle')->nullable();
            $t->date('registered_at')->nullable();
            $t->date('expires_at')->nullable();         // registry-authoritative, synced
            $t->boolean('auto_renew')->default(true);
            $t->foreignUuid('client_subscription_id')->nullable()->constrained()->nullOnDelete();
            $t->text('epp_auth_info')->nullable();      // encrypted transfer code
            $t->json('meta')->nullable();
            $t->unsignedBigInteger('legacy_id')->nullable()->index(); // WHMCS tbldomains.id
            $t->timestamps();
            $t->unique('name');
            $t->index(['tenant_id', 'status']);
            $t->index(['tenant_id', 'expires_at']);
        });

        Schema::create('domain_logs', function (Blueprint $t) {
            $t->uuid('id')->primary();
            $t->foreignUuid('tenant_id')->nullable()->constrained()->cascadeOnDelete();
            $t->foreignUuid('domain_id')->nullable()->constrained()->nullOnDelete();
            $t->string('action');
            $t->json('request')->nullable();            // sanitized
            $t->json('response')->nullable();
            $t->string('status');                       // success|failed
            $t->text('error')->nullable();
            $t->timestamps();
            $t->index(['tenant_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('domain_logs');
        Schema::dropIfExists('domains');
        Schema::dropIfExists('domain_tlds');
        Schema::dropIfExists('registrar_accounts');
    }
};
