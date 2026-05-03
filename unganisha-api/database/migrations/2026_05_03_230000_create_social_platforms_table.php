<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('social_platforms', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('tenant_id')->index();
            $table->string('name', 50);   // slug: 'instagram'
            $table->string('label', 100); // display: 'Instagram'
            $table->string('color', 50)->default('blue');
            $table->string('icon', 50)->default('brand-instagram'); // maps to Tabler icon
            $table->string('profile_url', 1000)->nullable();
            $table->boolean('is_active')->default(true);
            $table->unsignedTinyInteger('sort_order')->default(99);
            $table->unique(['tenant_id', 'name']);
            $table->timestamps();
        });

        // Seed the 5 default platforms for every existing tenant
        $defaults = [
            ['name' => 'instagram', 'label' => 'Instagram', 'color' => 'pink',  'icon' => 'brand-instagram', 'sort_order' => 1],
            ['name' => 'facebook',  'label' => 'Facebook',  'color' => 'blue',  'icon' => 'brand-facebook',  'sort_order' => 2],
            ['name' => 'threads',   'label' => 'Threads',   'color' => 'dark',  'icon' => 'brand-threads',   'sort_order' => 3],
            ['name' => 'x',         'label' => 'X (Twitter)', 'color' => 'gray', 'icon' => 'brand-x',        'sort_order' => 4],
            ['name' => 'tiktok',    'label' => 'TikTok',    'color' => 'red',   'icon' => 'brand-tiktok',    'sort_order' => 5],
        ];

        foreach (DB::table('tenants')->pluck('id') as $tenantId) {
            foreach ($defaults as $p) {
                DB::table('social_platforms')->insertOrIgnore([
                    'id'         => (string) Str::uuid(),
                    'tenant_id'  => $tenantId,
                    'profile_url'=> null,
                    'is_active'  => true,
                    ...$p,
                ]);
            }
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('social_platforms');
    }
};
