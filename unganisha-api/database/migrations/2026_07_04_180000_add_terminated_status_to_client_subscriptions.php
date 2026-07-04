<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * Widen client_subscriptions.status to include 'terminated' and 'fraud'.
     *
     * These states are already accepted by HostingServiceController::update()
     * validation (WHMCS-style hosting service admin) and 'terminated' is the
     * terminal state written by the subscriptions:terminate-abandoned command
     * (WHMCS "Auto Terminate" parity). Until now the enum silently truncated
     * them. Purely additive — no existing rows change.
     */
    public function up(): void
    {
        DB::statement("ALTER TABLE client_subscriptions MODIFY COLUMN status ENUM('pending','active','cancelled','suspended','terminated','fraud') DEFAULT 'pending'");
    }

    public function down(): void
    {
        // Fold the new terminal states back into 'cancelled' before narrowing
        // the enum so no row holds a value the column can no longer store.
        DB::statement("UPDATE client_subscriptions SET status = 'cancelled' WHERE status IN ('terminated','fraud')");
        DB::statement("ALTER TABLE client_subscriptions MODIFY COLUMN status ENUM('pending','active','cancelled','suspended') DEFAULT 'pending'");
    }
};
