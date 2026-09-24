<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/** Client portal "add my domain to my Linode server" requests, decided by staff. DATETIME (not TIMESTAMP) on purpose. */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('linode_domain_requests', function (Blueprint $t) {
            $t->uuid('id')->primary();
            $t->uuid('tenant_id')->index();
            $t->uuid('client_id')->index();
            $t->uuid('linode_resource_id')->index(); // the server
            $t->string('domain');
            $t->string('status', 20)->default('pending'); // pending|approved|rejected
            $t->uuid('requested_by')->nullable(); // client_users.id
            $t->uuid('decided_by')->nullable();   // users.id
            $t->dateTime('decided_at')->nullable();
            $t->string('note', 500)->nullable();
            $t->dateTime('created_at')->nullable();
            $t->dateTime('updated_at')->nullable();
            $t->index(['tenant_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('linode_domain_requests');
    }
};
