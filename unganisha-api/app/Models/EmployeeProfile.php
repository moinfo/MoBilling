<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class EmployeeProfile extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'user_id', 'employee_number', 'hire_date', 'department', 'position',
        'employment_type', 'national_id', 'nssf_number', 'tin_number', 'date_of_birth', 'gender',
        'next_of_kin_name', 'next_of_kin_phone', 'bank_name', 'bank_branch', 'bank_account_name',
        'bank_account_number', 'mobile_money_provider', 'mobile_money_number', 'termination_date', 'notes',
    ];

    protected $casts = [
        'hire_date' => 'date',
        'date_of_birth' => 'date',
        'termination_date' => 'date',
    ];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
