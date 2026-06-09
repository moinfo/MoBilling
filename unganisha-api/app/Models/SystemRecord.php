<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class SystemRecord extends Model
{
    use HasFactory, HasUuids, SoftDeletes, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'system_id', 'system_property_id', 'bank_account_id', 'created_by',
        'record_date', 'amount', 'notes', 'receipt_attachment_path',
    ];

    protected $casts = [
        'record_date' => 'date',
        'amount' => 'decimal:2',
    ];

    public function system()
    {
        return $this->belongsTo(System::class);
    }

    public function systemProperty()
    {
        return $this->belongsTo(SystemProperty::class);
    }

    public function bankAccount()
    {
        return $this->belongsTo(BankAccount::class);
    }

    public function createdBy()
    {
        return $this->belongsTo(User::class, 'created_by');
    }
}
