<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * FCM device tokens for the mobile apps.
 *
 * Polymorphic owner: a ClientUser (client portal app) today, a staff User
 * when the staff app ships. One row per (owner, token) — a token moves
 * between accounts when someone signs out and a different user signs in on
 * the same device, hence the unique index on token alone.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('device_tokens', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('tenant_id')->nullable()->index();
            $table->uuidMorphs('owner');
            $table->string('token', 255)->unique();
            $table->string('platform', 16)->nullable(); // ios | android
            $table->string('app', 32)->default('client_portal');
            $table->timestamp('last_seen_at')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('device_tokens');
    }
};
