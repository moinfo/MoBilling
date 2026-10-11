<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('product_services', function (Blueprint $table) {
            $table->string('linode_type')->nullable()->after('cpanel_package');
            $table->string('linode_region')->nullable()->after('linode_type');
            $table->string('linode_image')->nullable()->after('linode_region');
        });
    }

    public function down(): void
    {
        Schema::table('product_services', function (Blueprint $table) {
            $table->dropColumn(['linode_type', 'linode_region', 'linode_image']);
        });
    }
};
