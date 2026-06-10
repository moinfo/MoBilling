<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * A System Verification entity is a system being monitored — distinct from
     * the existing `systems` table (used by System Records). Each entity holds
     * the identifying details (name, domain, external client id) and a single
     * assigned staff member responsible for the daily check-in.
     */
    public function up(): void
    {
        Schema::create('system_verifications', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('name');
            $table->string('domain_name')->nullable();
            $table->string('client_id')->nullable();
            // The single staff currently responsible. Nullable so a system can
            // exist without an assigned owner; nullOnDelete keeps history alive
            // if the user is later removed.
            $table->foreignUuid('assigned_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->boolean('is_active')->default(true);
            $table->timestamps();
            $table->softDeletes();

            $table->index('tenant_id');
            $table->index('assigned_user_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('system_verifications');
    }
};
