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
    ];

    protected $casts = [
        'report_date' => 'date',
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
