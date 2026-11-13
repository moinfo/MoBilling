<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * A router with no owning client is still staff-managed only (the
     * original behavior) — this lets a tenant hand a specific router over
     * to one of their own clients to self-manage via the client portal,
     * without disturbing routers nobody has assigned yet.
     */
    public function up(): void
    {
        Schema::table('mikrotik_routers', function (Blueprint $table) {
            $table->foreignUuid('client_id')->nullable()->after('tenant_id')
                ->constrained()->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('mikrotik_routers', function (Blueprint $table) {
            $table->dropConstrainedForeignId('client_id');
        });
    }
};
