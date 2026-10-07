<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The assigned staff member needs to actually log in to the client's
 * system to check it, so the credentials live on the SystemVerification
 * record itself — not a one-off note somewhere. Password is encrypted at
 * rest (Model::$casts 'encrypted', not hashed) because it must be
 * decryptable to show to the assigned staff / admin, the same reasoning
 * as tenants.smtp_password.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('system_verifications', function (Blueprint $table) {
            $table->string('login_username')->nullable()->after('client_id');
            $table->text('login_password')->nullable()->after('login_username'); // encrypted cast, text for ciphertext length
        });
    }

    public function down(): void
    {
        Schema::table('system_verifications', function (Blueprint $table) {
            $table->dropColumn(['login_username', 'login_password']);
        });
    }
};
