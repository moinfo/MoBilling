<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class WhatsappVerifyAttempt extends Model
{
    protected $fillable = ['tenant_id', 'phone', 'failures', 'first_failed_at', 'last_failed_at', 'locked_until'];

    protected $casts = ['first_failed_at' => 'datetime', 'last_failed_at' => 'datetime', 'locked_until' => 'datetime'];
}
