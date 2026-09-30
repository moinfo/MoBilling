<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A client's application to become a white-label reseller — a request that,
 * once approved and provisioned (see ResellerProvisioningService), spawns a
 * brand-new Tenant selling MoBilling's own catalog at the reseller's own
 * retail prices, fulfilled on the SAME shared infrastructure Moinfotech
 * already uses. tenant_id here is the APPLICANT'S home tenant (Moinfotech),
 * not the new tenant being requested — provisioned_tenant_id links to that
 * once step 4 (provision) runs. DATETIME (not TIMESTAMP) columns throughout —
 * this codebase's MariaDB implicit-ON-UPDATE gotcha.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('reseller_applications', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('client_id')->constrained()->cascadeOnDelete();

            $table->string('requested_domain');
            $table->string('brand_name');
            $table->json('categories'); // subset of ['domain','hosting','email','linode']

            $table->string('contact_name');
            $table->string('contact_email');
            $table->string('contact_phone')->nullable();

            $table->enum('status', ['pending', 'approved', 'rejected', 'provisioned'])->default('pending');
            $table->text('staff_note')->nullable();
            $table->foreignUuid('decided_by')->nullable()->constrained('users')->nullOnDelete();
            $table->dateTime('decided_at')->nullable();

            $table->foreignUuid('provisioned_tenant_id')->nullable()->constrained('tenants')->nullOnDelete();

            $table->dateTime('created_at')->nullable();
            $table->dateTime('updated_at')->nullable();

            $table->index(['tenant_id', 'status']);
            $table->index(['client_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('reseller_applications');
    }
};
