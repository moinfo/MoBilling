<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Several Name.com API credentials per tenant (e.g. owner account + a second user).
 * Additive: the existing single row keeps working and becomes the default account.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('namecom_accounts', function (Blueprint $t) {
            $t->string('label', 60)->nullable()->after('tenant_id');
            $t->boolean('is_default')->default(false)->after('label');
        });

        // Plain index first so tenant_id lookups stay indexed, then drop the unique constraint.
        Schema::table('namecom_accounts', function (Blueprint $t) {
            $t->index('tenant_id', 'namecom_accounts_tenant_idx');
        });
        Schema::table('namecom_accounts', function (Blueprint $t) {
            $t->dropUnique('namecom_accounts_tenant_id_unique');
        });

        DB::table('namecom_accounts')->update(['label' => 'Default account', 'is_default' => true]);

        Schema::table('namecom_audit_logs', function (Blueprint $t) {
            $t->string('account_label', 60)->nullable()->after('namecom_account_id');
        });
    }

    public function down(): void
    {
        Schema::table('namecom_audit_logs', fn (Blueprint $t) => $t->dropColumn('account_label'));
        // Restoring the unique constraint would fail with >1 account per tenant; keep the extra rows out first.
        $dups = DB::table('namecom_accounts')->select('tenant_id')->groupBy('tenant_id')->havingRaw('count(*) > 1')->pluck('tenant_id');
        foreach ($dups as $tid) {
            $keep = DB::table('namecom_accounts')->where('tenant_id', $tid)->orderByDesc('is_default')->orderBy('created_at')->value('id');
            DB::table('namecom_accounts')->where('tenant_id', $tid)->where('id', '!=', $keep)->delete();
        }
        Schema::table('namecom_accounts', function (Blueprint $t) {
            $t->unique('tenant_id', 'namecom_accounts_tenant_id_unique');
        });
        Schema::table('namecom_accounts', function (Blueprint $t) {
            $t->dropIndex('namecom_accounts_tenant_idx');
            $t->dropColumn(['label', 'is_default']);
        });
    }
};
