<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('marketing_services', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('tenant_id');
            $table->string('name');
            $table->integer('sort_order')->default(0);
            $table->timestamps();

            $table->unique(['tenant_id', 'name']);
            $table->index('tenant_id');
        });

        // Seed default services for all existing tenants
        $defaults = [
            'MoBilling', 'Bulk SMS', 'Hosting', 'Web Design', 'CCTV',
            'POS System', 'E-File System', 'IT Support', 'Online Marketing', 'Other',
        ];

        $tenants = DB::table('tenants')->pluck('id');

        foreach ($tenants as $tenantId) {
            foreach ($defaults as $i => $name) {
                DB::table('marketing_services')->insertOrIgnore([
                    'id'         => (string) Str::uuid(),
                    'tenant_id'  => $tenantId,
                    'name'       => $name,
                    'sort_order' => $i,
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
            }
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('marketing_services');
    }
};
