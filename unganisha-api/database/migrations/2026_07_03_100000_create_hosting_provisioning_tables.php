<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * WHM/cPanel provisioning (docs/IMPLEMENTATION_PLAN.md §A0).
     */
    public function up(): void
    {
        Schema::create('servers', function (Blueprint $t) {
            $t->uuid('id')->primary();
            $t->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $t->string('name');
            $t->string('hostname');
            $t->unsignedInteger('port')->default(2087);
            $t->string('username');
            $t->text('api_token');                       // encrypted cast on model
            $t->json('nameservers')->nullable();
            $t->string('type')->default('whm_cpanel');
            $t->boolean('is_active')->default(true);
            $t->boolean('verify_ssl')->default(true);
            $t->unsignedBigInteger('legacy_id')->nullable()->index();
            $t->timestamps();
            $t->index(['tenant_id', 'is_active']);
        });

        Schema::table('product_services', function (Blueprint $t) {
            $t->string('provisioning_type')->default('none');   // none|whm_cpanel
            $t->foreignUuid('server_id')->nullable()->constrained('servers')->nullOnDelete();
            $t->string('cpanel_package')->nullable();
            $t->boolean('auto_provision')->default(false);
        });

        Schema::create('hosting_accounts', function (Blueprint $t) {
            $t->uuid('id')->primary();
            $t->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $t->foreignUuid('client_subscription_id')->constrained()->cascadeOnDelete();
            $t->foreignUuid('server_id')->constrained();
            $t->string('domain');
            $t->string('cpanel_username');
            $t->string('package')->nullable();
            $t->string('status')->default('pending');    // pending|active|suspended|terminated|failed
            $t->timestamp('last_synced_at')->nullable();
            $t->json('meta')->nullable();
            $t->unsignedBigInteger('legacy_id')->nullable()->index();
            $t->timestamps();
            $t->unique(['server_id', 'cpanel_username']);
            $t->index(['tenant_id', 'status']);
        });

        Schema::create('provisioning_logs', function (Blueprint $t) {
            $t->uuid('id')->primary();
            $t->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $t->foreignUuid('hosting_account_id')->nullable()->constrained()->nullOnDelete();
            $t->foreignUuid('server_id')->nullable()->constrained()->nullOnDelete();
            $t->string('action');
            $t->json('request')->nullable();             // sanitized — never tokens/passwords
            $t->json('response')->nullable();
            $t->string('status');                        // success|failed
            $t->text('error')->nullable();
            $t->timestamps();
            $t->index(['tenant_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('provisioning_logs');
        Schema::dropIfExists('hosting_accounts');
        Schema::table('product_services', function (Blueprint $t) {
            $t->dropConstrainedForeignId('server_id');
            $t->dropColumn(['provisioning_type', 'cpanel_package', 'auto_provision']);
        });
        Schema::dropIfExists('servers');
    }
};
