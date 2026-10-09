<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * A tenant admin's own daily closing figure, added without a developer
 * touching code — see SystemVerification::AVAILABLE_FIELDS for the four
 * built-in ones this extends, never replaces.
 */
class SystemVerificationFieldDefinition extends Model
{
    use HasFactory, HasUuids, SoftDeletes, BelongsToTenant;

    protected $fillable = ['tenant_id', 'key', 'label'];
}
