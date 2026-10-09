<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class SystemVerificationReport extends Model
{
    use HasFactory, HasUuids, SoftDeletes, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'system_verification_id', 'user_id',
        'report_date', 'status', 'notes',
        'cash', 'sales', 'credit', 'gain_loss', 'submitted_on_time',
        // Values for admin-defined custom fields (SystemVerificationFieldDefinition),
        // keyed by their `key` — the four built-in figures above are unaffected.
        'custom_values',
    ];

    protected $casts = [
        'report_date' => 'date',
        'cash' => 'decimal:2',
        'sales' => 'decimal:2',
        'credit' => 'decimal:2',
        'gain_loss' => 'decimal:2',
        'submitted_on_time' => 'boolean',
        'custom_values' => 'array',
    ];

    public function systemVerification()
    {
        return $this->belongsTo(SystemVerification::class);
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }
}
