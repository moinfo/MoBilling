<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class ClientSubscription extends Model
{
    use HasFactory, HasUuids, SoftDeletes, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'client_id', 'product_service_id',
        'label', 'quantity', 'start_date', 'status', 'metadata',
    ];

    protected $casts = [
        'start_date' => 'date',
        'metadata' => 'array',
        'quantity' => 'integer',
    ];

    public function client()
    {
        return $this->belongsTo(Client::class);
    }

    public function productService()
    {
        return $this->belongsTo(ProductService::class);
    }

    public function scopeActive($query)
    {
        return $query->where('status', 'active');
    }
}
