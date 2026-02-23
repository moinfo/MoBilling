<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Notifications\Notifiable;

class Client extends Model
{
    use HasFactory, HasUuids, SoftDeletes, BelongsToTenant, Notifiable;

    protected $fillable = [
        'tenant_id', 'name', 'email', 'phone',
        'address', 'tax_id',
    ];

    public function documents()
    {
        return $this->hasMany(Document::class);
    }
}
