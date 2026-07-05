<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('domain_registry_events', function (Blueprint $table) {
            $table->uuid('id')->primary();
            // platform registrar (nullable tenant, like registrar_accounts)
            $table->foreignUuid('tenant_id')->nullable();
            $table->string('registry_msg_id')->nullable()->unique();
            $table->string('msg_type', 60)->nullable();
            $table->timestamp('msg_date')->nullable();
            $table->string('domain')->nullable();
            $table->text('text')->nullable();
            $table->json('data')->nullable();
            $table->boolean('acked')->default(false);   // dequeued at the registry
            $table->boolean('acted')->default(false);   // MoBilling reacted (e.g. flagged the domain)
            $table->timestamps();

            $table->index('domain');
            $table->index('msg_type');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('domain_registry_events');
    }
};
