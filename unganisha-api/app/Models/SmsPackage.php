<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class SmsPackage extends Model
{
    use HasUuids;

    protected $fillable = [
        'name', 'price_per_sms', 'min_quantity', 'max_quantity',
        'is_active', 'sort_order',
    ];

    protected $casts = [
        'price_per_sms' => 'decimal:2',
        'is_active' => 'boolean',
    ];

    public function scopeActive($query)
    {
        return $query->where('is_active', true);
    }

    public function scopeOrdered($query)
    {
        return $query->orderBy('sort_order')->orderBy('min_quantity');
    }

    public static function forQuantity(int $qty): ?self
    {
        return static::active()
            ->where('min_quantity', '<=', $qty)
            ->where(function ($q) use ($qty) {
                $q->whereNull('max_quantity')
                  ->orWhere('max_quantity', '>=', $qty);
            })
            ->orderByDesc('min_quantity')
            ->first();
    }
}
