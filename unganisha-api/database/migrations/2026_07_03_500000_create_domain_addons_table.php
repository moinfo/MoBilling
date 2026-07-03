<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

return new class extends Migration
{
    /**
     * Domain addons offered during domain configuration (WHMCS-style).
     * NULL tenant_id = platform defaults, tenant rows override/extend.
     */
    public function up(): void
    {
        Schema::create('domain_addons', function (Blueprint $t) {
            $t->uuid('id')->primary();
            $t->foreignUuid('tenant_id')->nullable()->constrained()->cascadeOnDelete();
            $t->string('name');
            $t->text('description')->nullable();
            $t->decimal('price', 12, 2)->default(0);
            $t->boolean('is_free')->default(true);
            $t->boolean('is_active')->default(true);
            $t->unsignedTinyInteger('sort')->default(0);
            $t->timestamps();
        });

        foreach ([
            ['DNS Management', 'External DNS hosting can help speed up your website and improve availability with increased redundancy.', 1],
            ['Email Forwarding', 'Forward email sent to your domain to another email address of your choice.', 2],
            ['ID Protection', 'Keep your personal contact details private in the public domain registry.', 3],
        ] as [$name, $desc, $sort]) {
            DB::table('domain_addons')->insert([
                'id' => (string) Str::uuid7(), 'tenant_id' => null,
                'name' => $name, 'description' => $desc,
                'price' => 0, 'is_free' => true, 'is_active' => true, 'sort' => $sort,
                'created_at' => now(), 'updated_at' => now(),
            ]);
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('domain_addons');
    }
};
