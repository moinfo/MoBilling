<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('tickets', function (Blueprint $t) {
            $t->uuid('id')->primary();
            $t->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $t->foreignUuid('client_id')->constrained()->cascadeOnDelete();
            $t->string('ticket_number');                    // per-tenant, e.g. TKT-0001
            $t->string('subject');
            $t->string('status')->default('open');          // open|answered|customer_reply|closed
            $t->string('priority')->default('medium');      // low|medium|high
            $t->foreignUuid('opened_by')->nullable()->constrained('client_users')->nullOnDelete();
            $t->foreignUuid('assigned_to')->nullable()->constrained('users')->nullOnDelete();
            $t->timestamp('last_reply_at')->nullable();
            $t->timestamps();
            $t->unique(['tenant_id', 'ticket_number']);
            $t->index(['tenant_id', 'status']);
            $t->index(['client_id', 'status']);
        });

        Schema::create('ticket_replies', function (Blueprint $t) {
            $t->uuid('id')->primary();
            $t->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $t->foreignUuid('ticket_id')->constrained()->cascadeOnDelete();
            $t->string('author_type');                      // staff|client
            $t->foreignUuid('user_id')->nullable()->constrained('users')->nullOnDelete();
            $t->foreignUuid('client_user_id')->nullable()->constrained('client_users')->nullOnDelete();
            $t->text('message');
            $t->timestamps();
            $t->index(['ticket_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('ticket_replies');
        Schema::dropIfExists('tickets');
    }
};
