<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class SystemVerification extends Model
{
    use HasFactory, HasUuids, SoftDeletes, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'name', 'domain_name', 'client_id',
        'assigned_user_id', 'is_active',
    ];

    protected $casts = [
        'is_active' => 'boolean',
    ];

    public function assignedUser()
    {
        return $this->belongsTo(User::class, 'assigned_user_id');
    }

    public function reports()
    {
        return $this->hasMany(SystemVerificationReport::class);
    }

    public function todaysReport()
    {
        return $this->hasOne(SystemVerificationReport::class)
            ->whereDate('report_date', today());
    }
}
