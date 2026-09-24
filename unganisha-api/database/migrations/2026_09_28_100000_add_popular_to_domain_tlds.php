<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/** Popular-TLD flag + display order for domain search. Additive; the seed only marks EXISTING rows. */
return new class extends Migration
{
    private array $popular = ['com', 'net', 'org', 'co.tz', 'tz', 'info', 'biz', 'io', 'co', 'online', 'site', 'shop', 'store', 'app', 'dev'];

    public function up(): void
    {
        Schema::table('domain_tlds', function (Blueprint $t) {
            $t->boolean('is_popular')->default(false);
            $t->unsignedSmallInteger('sort_order')->default(1000);
        });

        foreach ($this->popular as $i => $tld) {
            DB::table('domain_tlds')->where('tld', $tld)->update(['is_popular' => true, 'sort_order' => ($i + 1) * 10]);
        }
    }

    public function down(): void
    {
        Schema::table('domain_tlds', function (Blueprint $t) {
            $t->dropColumn(['is_popular', 'sort_order']);
        });
    }
};
