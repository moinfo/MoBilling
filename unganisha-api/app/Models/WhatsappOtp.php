<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class WhatsappOtp extends Model
{
    public const UPDATED_AT = null;

    protected $fillable = ['tenant_id', 'phone', 'client_id', 'purpose', 'code_hash', 'attempts', 'expires_at', 'used_at'];

    protected $hidden = ['code_hash'];

    protected $casts = ['expires_at' => 'datetime', 'used_at' => 'datetime'];
}
