<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('linode_accounts', function (Blueprint $t) {
            $t->uuid('id')->primary();
            $t->uuid('tenant_id')->index();
            $t->string('label');
            $t->text('token'); // encrypted cast, never exposed
            $t->string('token_hint', 8)->nullable();
            $t->string('soa_email')->nullable();
            $t->string('status', 20)->default('active'); // active|invalid
            $t->string('status_message')->nullable();
            $t->timestamp('last_verified_at')->nullable();
            $t->timestamp('last_synced_at')->nullable();
            $t->timestamps();
        });

        Schema::create('linode_resources', function (Blueprint $t) {
            $t->uuid('id')->primary();
            $t->uuid('tenant_id')->index();
            $t->uuid('linode_account_id')->index();
            $t->string('type', 20); // instance|domain
            $t->string('remote_id', 64);
            $t->string('label');
            $t->string('status', 30)->nullable();
            $t->string('region', 40)->nullable();
            $t->string('plan', 60)->nullable();
            $t->json('ipv4')->nullable();
            $t->string('ipv6')->nullable();
            $t->json('tags')->nullable();
            $t->json('meta')->nullable();
            // Phase 2 mapping to our own customers.
            $t->uuid('client_id')->nullable()->index();
            $t->uuid('client_subscription_id')->nullable()->index();
            $t->uuid('domain_id')->nullable()->index();
            $t->timestamp('synced_at')->nullable();
            $t->timestamps();
            $t->unique(['linode_account_id', 'type', 'remote_id'], 'linode_res_unique');
        });

        Schema::create('linode_audit_logs', function (Blueprint $t) {
            $t->uuid('id')->primary();
            $t->uuid('tenant_id')->index();
            $t->uuid('user_id')->nullable();
            $t->uuid('linode_account_id')->nullable()->index();
            $t->string('action', 60);
            $t->string('target')->nullable();
            $t->json('request')->nullable();
            $t->unsignedSmallInteger('response_status')->nullable();
            $t->string('error')->nullable();
            $t->timestamp('created_at')->useCurrent();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('linode_audit_logs');
        Schema::dropIfExists('linode_resources');
        Schema::dropIfExists('linode_accounts');
    }
};
