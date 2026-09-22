<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * MariaDB gives the first TIMESTAMP-type column in a table an implicit
 * "DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP" unless told otherwise — expires_at
 * was that first column, so ANY update to a session row that didn't also explicitly re-set
 * expires_at in the same query silently reset it to "now", expiring the session almost
 * immediately. This likely explains an earlier unreproducible report of the language prompt
 * reappearing mid-flow: the session had silently "expired" seconds after a flow/state-only
 * save, so the next reply started a fresh conversation instead of continuing. DATETIME columns
 * never get this implicit behavior (found and confirmed live in MoSMS's sibling session table).
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::statement('ALTER TABLE whatsapp_renewal_sessions MODIFY expires_at DATETIME NOT NULL');
    }

    public function down(): void
    {
        DB::statement('ALTER TABLE whatsapp_renewal_sessions MODIFY expires_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP');
    }
};
