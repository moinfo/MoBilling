<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * White-label font choice for a reseller's own site/portal — restricted to
 * a fixed allow-list of fonts already bundled in the frontend (see
 * Settings::CompanyTab / branding.ts), never a free-text CSS value.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->string('brand_font')->nullable()->after('logo_path');
            $table->string('brand_font_size')->nullable()->after('brand_font');
        });
    }

    public function down(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->dropColumn(['brand_font', 'brand_font_size']);
        });
    }
};
