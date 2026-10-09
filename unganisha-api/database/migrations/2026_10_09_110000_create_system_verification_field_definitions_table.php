<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Lets each tenant's admin add their OWN daily closing figures (beyond the
 * four built-in ones in SystemVerification::AVAILABLE_FIELDS) without a
 * developer touching code. A system's required_fields can reference a
 * definition's `key` the same way it references a built-in key; the actual
 * value goes in system_verification_reports.custom_values (JSON), keyed the
 * same way — see SystemVerificationReport.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('system_verification_field_definitions', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('key');
            $table->string('label');
            $table->timestamps();
            $table->softDeletes();

            $table->unique(['tenant_id', 'key']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('system_verification_field_definitions');
    }
};
