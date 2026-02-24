<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // 1. Make tenant_id nullable on users (super_admin has no tenant)
        Schema::table('users', function (Blueprint $table) {
            $table->dropForeign(['tenant_id']);
        });
        Schema::table('users', function (Blueprint $table) {
            $table->uuid('tenant_id')->nullable()->change();
            $table->foreign('tenant_id')->references('id')->on('tenants')->cascadeOnDelete();
        });

        // 2. Add super_admin to role enum
        DB::statement("ALTER TABLE users MODIFY COLUMN role ENUM('admin', 'user', 'super_admin') DEFAULT 'user'");

        // 3. Add is_active to tenants
        Schema::table('tenants', function (Blueprint $table) {
            $table->boolean('is_active')->default(true)->after('currency');
        });
    }

    public function down(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->dropColumn('is_active');
        });

        DB::statement("ALTER TABLE users MODIFY COLUMN role ENUM('admin', 'user') DEFAULT 'user'");

        // Revert tenant_id to non-nullable (will fail if nulls exist)
        Schema::table('users', function (Blueprint $table) {
            $table->dropForeign(['tenant_id']);
        });
        Schema::table('users', function (Blueprint $table) {
            $table->uuid('tenant_id')->nullable(false)->change();
            $table->foreign('tenant_id')->references('id')->on('tenants')->cascadeOnDelete();
        });
    }
};
