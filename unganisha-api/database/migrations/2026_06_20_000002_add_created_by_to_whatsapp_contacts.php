<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('whatsapp_contacts', function (Blueprint $table) {
            // The user who registered the contact. Nullable so existing rows and
            // deleted users don't break; drives per-user visibility.
            $table->foreignUuid('created_by')->nullable()->after('assigned_to')
                ->constrained('users')->nullOnDelete();
            $table->index(['tenant_id', 'created_by']);
        });

        // Best-effort backfill for existing contacts: attribute them to their
        // assigned owner so those staff still see their leads after this change.
        DB::table('whatsapp_contacts')
            ->whereNull('created_by')
            ->whereNotNull('assigned_to')
            ->update(['created_by' => DB::raw('assigned_to')]);
    }

    public function down(): void
    {
        Schema::table('whatsapp_contacts', function (Blueprint $table) {
            $table->dropConstrainedForeignId('created_by');
        });
    }
};
