<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * WHMCS-style structured fields, purely additive — the existing `name` and
 * `address` columns stay as the primary display fields used everywhere
 * (invoices, PDFs, notifications), so nothing breaks for clients that never
 * fill these in. When present, they let staff enter/print a proper
 * first/last/company + address1-2/city/state/postcode/country breakdown,
 * matching what WHMCS originally captured (see WhmcsImporter::importClients,
 * which flattens these exact fields into `name`/`address` on import).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('clients', function (Blueprint $table) {
            $table->string('first_name')->nullable()->after('name');
            $table->string('last_name')->nullable()->after('first_name');
            $table->string('company_name')->nullable()->after('last_name');
            $table->string('address_1')->nullable()->after('address');
            $table->string('address_2')->nullable()->after('address_1');
            $table->string('city')->nullable()->after('address_2');
            $table->string('state')->nullable()->after('city');
            $table->string('postcode')->nullable()->after('state');
            $table->string('country', 2)->nullable()->after('postcode');
        });
    }

    public function down(): void
    {
        Schema::table('clients', function (Blueprint $table) {
            $table->dropColumn([
                'first_name', 'last_name', 'company_name',
                'address_1', 'address_2', 'city', 'state', 'postcode', 'country',
            ]);
        });
    }
};
