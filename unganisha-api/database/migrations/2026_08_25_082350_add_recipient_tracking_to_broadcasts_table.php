<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('broadcasts', function (Blueprint $table) {
            $table->json('sent_client_ids')->nullable()->after('sms_body');
            $table->json('failed_client_ids')->nullable()->after('sent_client_ids');
            $table->foreignUuid('retry_of_broadcast_id')->nullable()->after('failed_client_ids')
                ->constrained('broadcasts')->nullOnDelete();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('broadcasts', function (Blueprint $table) {
            $table->dropConstrainedForeignId('retry_of_broadcast_id');
            $table->dropColumn(['sent_client_ids', 'failed_client_ids']);
        });
    }
};
