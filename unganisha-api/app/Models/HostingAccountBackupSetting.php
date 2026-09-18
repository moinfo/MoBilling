<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class HostingAccountBackupSetting extends Model
{
    use HasUuids, BelongsToTenant;

    public const DEFAULT_DAILY_RETENTION_DAYS = 7;

    protected $fillable = [
        'tenant_id', 'hosting_account_id', 'daily_retention_days', 'keep_weekly', 'keep_monthly',
    ];

    protected $casts = [
        'daily_retention_days' => 'integer',
        'keep_weekly'          => 'boolean',
        'keep_monthly'         => 'boolean',
    ];

    public function hostingAccount()
    {
        return $this->belongsTo(HostingAccount::class);
    }
}
