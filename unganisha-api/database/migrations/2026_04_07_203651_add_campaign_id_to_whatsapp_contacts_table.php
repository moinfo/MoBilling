<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('whatsapp_contacts', function (Blueprint $table) {
            $table->foreignUuid('campaign_id')->nullable()->after('ad_campaign')
                ->constrained('whatsapp_campaigns')->nullOnDelete();
            $table->dropColumn('ad_campaign');
        });
    }

    public function down(): void
    {
        Schema::table('whatsapp_contacts', function (Blueprint $table) {
            $table->dropForeign(['campaign_id']);
            $table->dropColumn('campaign_id');
            $table->string('ad_campaign')->nullable();
        });
    }
};
