<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * An admin must review and approve an unpaid invoice as legitimately collectible before it
 * can be assigned to staff for follow-up (FollowupController::store() now checks this) — the
 * customer requested this explicitly: "before I assign, I need to confirm the client really
 * owes this and should pay it."
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('documents', function (Blueprint $table) {
            $table->foreignUuid('collection_reviewed_by')->nullable()->after('overdue_stage')
                ->constrained('users')->nullOnDelete();
            $table->timestamp('collection_reviewed_at')->nullable()->after('collection_reviewed_by');
            $table->text('collection_review_notes')->nullable()->after('collection_reviewed_at');
        });
    }

    public function down(): void
    {
        Schema::table('documents', function (Blueprint $table) {
            $table->dropConstrainedForeignId('collection_reviewed_by');
            $table->dropColumn(['collection_reviewed_at', 'collection_review_notes']);
        });
    }
};
