<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Update-check catalog for self-hosted installs — MoBilling's own super
 * admin publishes a new row here (version, changelog, a download_url the
 * admin uploads/hosts elsewhere) each time a distributable package is cut.
 * A self-hosted install compares its own config('app.version') against
 * GET /releases/latest to show "update available"; this is notify-only for
 * now (no in-app auto-apply — too risky without more infrastructure), so
 * download_url is just a link the customer's admin follows manually.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('releases', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('version')->unique();
            $table->text('changelog')->nullable();
            $table->string('download_url')->nullable();
            $table->boolean('is_active')->default(true);
            $table->timestamp('released_at');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('releases');
    }
};
