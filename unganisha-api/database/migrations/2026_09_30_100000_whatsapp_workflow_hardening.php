<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * WhatsApp workflow hardening (additive only — no existing column or table is altered or dropped):
 *  - whatsapp_verify_attempts: persistent per-(tenant, phone) verification failure counter + lock, so
 *    deleting/recreating the session row can never reset the brute-force counter.
 *  - whatsapp_reminder_targets: which domain(s) a bare "1" reply to an expiry reminder refers to, kept
 *    apart from the live conversation session (the reminder cron used to overwrite session.items).
 *  - whatsapp_renewal_sessions.flow_expires_at: per-flow step TTL, independent of the 30-day login.
 *  - coupons.max_uses_per_client: optional per-client redemption cap.
 *  - users.whatsapp_pin_*: persistent staff PIN failure counter + lock.
 *
 * DATETIME (not TIMESTAMP) throughout: on MariaDB the first TIMESTAMP column silently gets
 * ON UPDATE CURRENT_TIMESTAMP (see 2026_09_22_130000).
 */
return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasTable('whatsapp_verify_attempts')) {
            Schema::create('whatsapp_verify_attempts', function (Blueprint $table) {
                $table->id();
                $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
                $table->string('phone', 32);
                $table->unsignedSmallInteger('failures')->default(0);
                $table->dateTime('first_failed_at')->nullable();
                $table->dateTime('last_failed_at')->nullable();
                $table->dateTime('locked_until')->nullable();
                $table->dateTime('created_at')->nullable();
                $table->dateTime('updated_at')->nullable();

                $table->unique(['tenant_id', 'phone']);
            });
        }

        if (!Schema::hasTable('whatsapp_reminder_targets')) {
            Schema::create('whatsapp_reminder_targets', function (Blueprint $table) {
                $table->id();
                $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
                $table->string('phone', 32);
                $table->uuid('client_id');
                $table->uuid('domain_id');
                $table->dateTime('expires_at');
                $table->dateTime('created_at')->nullable();

                $table->unique(['tenant_id', 'phone', 'domain_id']);
                $table->index('expires_at');
            });
        }

        if (!Schema::hasColumn('whatsapp_renewal_sessions', 'flow_expires_at')) {
            Schema::table('whatsapp_renewal_sessions', function (Blueprint $table) {
                $table->dateTime('flow_expires_at')->nullable();
            });
        }

        if (!Schema::hasColumn('coupons', 'max_uses_per_client')) {
            Schema::table('coupons', function (Blueprint $table) {
                $table->unsignedInteger('max_uses_per_client')->nullable();
            });
        }

        if (!Schema::hasColumn('users', 'whatsapp_pin_failed_count')) {
            Schema::table('users', function (Blueprint $table) {
                $table->unsignedTinyInteger('whatsapp_pin_failed_count')->default(0);
                $table->dateTime('whatsapp_pin_failed_at')->nullable();
                $table->dateTime('whatsapp_pin_locked_until')->nullable();
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('whatsapp_verify_attempts');
        Schema::dropIfExists('whatsapp_reminder_targets');

        if (Schema::hasColumn('whatsapp_renewal_sessions', 'flow_expires_at')) {
            Schema::table('whatsapp_renewal_sessions', fn (Blueprint $t) => $t->dropColumn('flow_expires_at'));
        }
        if (Schema::hasColumn('coupons', 'max_uses_per_client')) {
            Schema::table('coupons', fn (Blueprint $t) => $t->dropColumn('max_uses_per_client'));
        }
        if (Schema::hasColumn('users', 'whatsapp_pin_failed_count')) {
            Schema::table('users', fn (Blueprint $t) => $t->dropColumn(['whatsapp_pin_failed_count', 'whatsapp_pin_failed_at', 'whatsapp_pin_locked_until']));
        }
    }
};
