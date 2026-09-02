<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * A TLD with no registrar driver behind it (gTLDs — com/net/org here;
     * only .tz is FRED-backed). order()/check() skip the registry call for
     * these, and the resulting Domain gets meta.unmanaged = true so
     * DocumentObserver already knows (pre-existing logic) to skip EPP
     * dispatch on payment rather than firing a job guaranteed to fail.
     */
    public function up(): void
    {
        Schema::table('domain_tlds', function (Blueprint $table) {
            $table->boolean('is_unmanaged')->default(false)->after('tld');
        });

        // com/net/org were deactivated because ordering them always failed
        // outright against FRED — re-activate now that ordering them
        // correctly routes to manual fulfilment instead.
        DB::table('domain_tlds')
            ->whereIn('tld', ['com', 'net', 'org'])
            ->update(['is_unmanaged' => true, 'is_active' => true]);
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('domain_tlds', function (Blueprint $table) {
            $table->dropColumn('is_unmanaged');
        });
    }
};
