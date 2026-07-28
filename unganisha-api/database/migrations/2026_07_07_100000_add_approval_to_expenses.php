<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Administrator approval for petty-cash expenses. New petty-cash expenses start
 * 'pending' and only reduce the official (verified) balance once 'approved'; a
 * 'rejected' expense never counts. Non-petty-cash expenses need no approval, so
 * they (and all pre-existing rows) are marked 'approved'.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('expenses', function (Blueprint $table) {
            $table->string('approval_status')->default('approved')->after('amount'); // pending|approved|rejected
            $table->foreignUuid('recorded_by')->nullable()->after('approval_status')->constrained('users')->nullOnDelete();
            $table->foreignUuid('approved_by')->nullable()->after('recorded_by')->constrained('users')->nullOnDelete();
            $table->timestamp('approved_at')->nullable()->after('approved_by');
            $table->string('rejection_reason')->nullable()->after('approved_at');
            $table->index(['tenant_id', 'approval_status']);
        });

        // Existing rows were already accepted before approval existed → approved.
        DB::table('expenses')->update(['approval_status' => 'approved']);
    }

    public function down(): void
    {
        Schema::table('expenses', function (Blueprint $table) {
            $table->dropIndex(['tenant_id', 'approval_status']);
            $table->dropConstrainedForeignId('recorded_by');
            $table->dropConstrainedForeignId('approved_by');
            $table->dropColumn(['approval_status', 'approved_at', 'rejection_reason']);
        });
    }
};
