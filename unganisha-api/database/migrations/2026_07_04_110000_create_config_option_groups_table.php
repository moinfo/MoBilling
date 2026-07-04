<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Configurable option groups (WHMCS-parity): a tenant-defined bundle of
     * options (e.g. "Server Specs" containing RAM, Disk, Extra Mailboxes) that
     * is assigned to products and configured by clients at order time.
     */
    public function up(): void
    {
        Schema::create('config_option_groups', function (Blueprint $t) {
            $t->uuid('id')->primary();
            $t->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $t->string('name');
            $t->text('description')->nullable();
            $t->boolean('is_active')->default(true);
            $t->timestamps();
            $t->softDeletes();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('config_option_groups');
    }
};
