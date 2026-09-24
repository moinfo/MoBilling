<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/** Name.com integration (nameserver management for linked domains). Additive only. */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('namecom_accounts', function (Blueprint $t) {
            $t->uuid('id')->primary();
            $t->uuid('tenant_id')->unique();
            $t->string('username', 100);
            $t->text('token'); // encrypted cast, write-only, never exposed
            $t->string('token_hint', 8)->nullable();
            $t->boolean('is_sandbox')->default(false);
            $t->string('status', 20)->default('active'); // active|invalid
            $t->string('status_message')->nullable();
            $t->timestamp('last_verified_at')->nullable();
            $t->timestamps();
        });

        Schema::create('namecom_audit_logs', function (Blueprint $t) {
            $t->uuid('id')->primary();
            $t->uuid('tenant_id')->index();
            $t->uuid('user_id')->nullable();
            $t->uuid('namecom_account_id')->nullable()->index();
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
        Schema::dropIfExists('namecom_audit_logs');
        Schema::dropIfExists('namecom_accounts');
    }
};
