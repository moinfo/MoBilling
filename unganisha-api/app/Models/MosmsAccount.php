<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class MosmsAccount extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'mosms_tenant_id', 'email', 'token', 'sender', 'custom_template_id',
    ];

    protected $casts = [
        'token' => 'encrypted',
    ];

    protected $hidden = ['token'];

    public function isLinked(): bool
    {
        return !empty($this->token);
    }
}
