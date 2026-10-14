<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('communication_logs', function (Blueprint $table) {
            // MoSMS's own internal message id — SMS gets this back synchronously at
            // send time. Used to match MoSMS's later delivery-status push back to
            // this row (deliberately MoSMS's own id, not the telco's gateway id,
            // which isn't guaranteed to exist yet when MoSMS first responds to us).
            $table->string('mosms_message_id')->nullable()->after('error');
            // WhatsApp sends are queued on MoSMS's side, so no id exists yet when we
            // send — we mint this ourselves and MoSMS echoes it back in the later
            // delivery-status push, which is how we match it back to this row.
            $table->string('client_ref')->nullable()->after('mosms_message_id');
            // 'sent'/'failed' above is just "did the API call succeed" — this is the
            // real carrier/WhatsApp outcome, filled in later by MoSMS's webhook push.
            $table->string('delivery_status')->nullable()->after('client_ref');
            $table->timestamp('delivered_at')->nullable()->after('delivery_status');
            $table->text('delivery_error')->nullable()->after('delivered_at');
            $table->timestamp('updated_at')->nullable()->after('delivery_error');

            $table->index('mosms_message_id');
            $table->index('client_ref');
        });
    }

    public function down(): void
    {
        Schema::table('communication_logs', function (Blueprint $table) {
            $table->dropIndex(['mosms_message_id']);
            $table->dropIndex(['client_ref']);
            $table->dropColumn(['mosms_message_id', 'client_ref', 'delivery_status', 'delivered_at', 'delivery_error', 'updated_at']);
        });
    }
};
