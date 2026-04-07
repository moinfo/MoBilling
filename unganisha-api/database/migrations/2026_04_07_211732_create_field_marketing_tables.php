<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Daily field sessions — one per officer per day
        Schema::create('field_sessions', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('officer_id')->constrained('users')->cascadeOnDelete();
            $table->date('visit_date');
            $table->string('area');                  // location covered that day
            $table->text('summary')->nullable();
            $table->text('challenges')->nullable();
            $table->text('recommendations')->nullable();
            $table->timestamps();
        });

        // Individual business visits within a session
        Schema::create('field_visits', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('session_id')->constrained('field_sessions')->cascadeOnDelete();
            $table->foreignUuid('officer_id')->constrained('users')->cascadeOnDelete();
            $table->string('business_name');
            $table->string('location');
            $table->string('phone')->nullable();
            $table->json('services');                // array of services interested in
            $table->text('feedback')->nullable();
            $table->enum('status', [
                'interested',
                'not_interested',
                'follow_up',
                'converted',
            ])->default('interested');
            $table->foreignUuid('client_id')->nullable()->constrained('clients')->nullOnDelete();
            $table->timestamps();
        });

        // Monthly targets per officer — goal = clients won
        Schema::create('field_targets', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('officer_id')->constrained('users')->cascadeOnDelete();
            $table->unsignedTinyInteger('month');    // 1–12
            $table->unsignedSmallInteger('year');
            $table->unsignedInteger('target_clients'); // clients to win this month
            $table->timestamps();
            $table->unique(['tenant_id', 'officer_id', 'month', 'year']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('field_visits');
        Schema::dropIfExists('field_sessions');
        Schema::dropIfExists('field_targets');
    }
};
