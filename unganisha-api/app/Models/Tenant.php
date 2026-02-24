<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Tenant extends Model
{
    use HasFactory, HasUuids, SoftDeletes;

    protected $fillable = [
        'name', 'email', 'phone', 'address',
        'logo_url', 'tax_id', 'currency', 'is_active',
        'email_enabled', 'smtp_host', 'smtp_port', 'smtp_username',
        'smtp_password', 'smtp_encryption', 'smtp_from_email', 'smtp_from_name',
        'sms_enabled', 'gateway_email', 'gateway_username', 'sender_id', 'sms_authorization',
    ];

    protected $hidden = [
        'smtp_password',
        'sms_authorization',
    ];

    protected $casts = [
        'is_active' => 'boolean',
        'email_enabled' => 'boolean',
        'sms_enabled' => 'boolean',
        'smtp_password' => 'encrypted',
        'sms_authorization' => 'encrypted',
    ];

    public function users()
    {
        return $this->hasMany(User::class);
    }
}
