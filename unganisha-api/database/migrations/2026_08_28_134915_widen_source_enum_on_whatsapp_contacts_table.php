<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * The original table only allowed 'whatsapp_ad', 'direct', 'referral',
     * 'other' — instagram/facebook/social_media were added to the frontend
     * dropdown and the controller's validation rule at some point, but the
     * actual DB enum was never widened to match. Passed validation, then
     * failed the insert itself with "Data truncated for column 'source'".
     */
    public function up(): void
    {
        DB::statement("ALTER TABLE whatsapp_contacts MODIFY source ENUM('whatsapp_ad', 'instagram', 'facebook', 'social_media', 'direct', 'referral', 'other') NOT NULL DEFAULT 'whatsapp_ad'");
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        DB::statement("ALTER TABLE whatsapp_contacts MODIFY source ENUM('whatsapp_ad', 'direct', 'referral', 'other') NOT NULL DEFAULT 'whatsapp_ad'");
    }
};
