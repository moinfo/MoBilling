<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/** Per-operation manual price overrides (register/renew/transfer) for Name.com TLDs. Additive. */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('domain_tlds', function (Blueprint $t) {
            $t->json('overridden_ops')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('domain_tlds', function (Blueprint $t) {
            $t->dropColumn('overridden_ops');
        });
    }
};
