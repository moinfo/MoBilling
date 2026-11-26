<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('clients', function (Blueprint $table) {
            // Cached FRED/.tz registry contact handle for this client (see
            // FredHttpDriver::createContact()) — created once on a client's
            // first .tz domain registration, then reused for every later
            // domain so they all share one real per-client registrant
            // instead of the reseller's own CONTACT-MOINFOTECH.
            $table->string('registry_contact_id')->nullable()->after('tax_id');
        });
    }

    public function down(): void
    {
        Schema::table('clients', function (Blueprint $table) {
            $table->dropColumn('registry_contact_id');
        });
    }
};
