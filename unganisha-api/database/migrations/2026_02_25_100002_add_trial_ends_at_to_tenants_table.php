<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->timestamp('trial_ends_at')->nullable()->after('is_active');
        });

        // Backfill existing tenants with 7-day trial from now
        DB::table('tenants')
            ->whereNull('trial_ends_at')
            ->update(['trial_ends_at' => now()->addDays(7)]);
    }

    public function down(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->dropColumn('trial_ends_at');
        });
    }
};
