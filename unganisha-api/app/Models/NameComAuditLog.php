<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class NameComAuditLog extends Model
{
    use HasUuids, BelongsToTenant;

    public const UPDATED_AT = null;

    protected $table = 'namecom_audit_logs';

    protected $fillable = ['tenant_id', 'user_id', 'namecom_account_id', 'account_label', 'action', 'target', 'request', 'response_status', 'error'];

    protected $casts = ['request' => 'array'];

    /** Every row records WHICH Name.com account it went through. */
    protected static function booted(): void
    {
        static::creating(function (self $row) {
            if ($row->namecom_account_id && !$row->account_label) {
                $a = NameComAccount::withoutGlobalScopes()->find($row->namecom_account_id);
                if ($a) $row->account_label = mb_substr($a->displayLabel(), 0, 60);
            }
        });
    }
}
