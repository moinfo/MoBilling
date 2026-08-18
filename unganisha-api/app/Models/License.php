<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class License extends Model
{
    use HasUuids;

    protected $fillable = [
        'license_key', 'customer_name', 'customer_email', 'product',
        'domain', 'status', 'expires_at', 'last_validated_at', 'notes',
    ];

    protected $casts = [
        'expires_at' => 'date',
        'last_validated_at' => 'datetime',
    ];

    public function activations(): HasMany
    {
        return $this->hasMany(LicenseActivation::class);
    }

    public function isExpired(): bool
    {
        return $this->expires_at !== null && $this->expires_at->isPast();
    }

    public static function generateKey(): string
    {
        do {
            $key = 'MB-' . collect(range(1, 4))
                ->map(fn () => strtoupper(substr(bin2hex(random_bytes(4)), 0, 4)))
                ->implode('-');
        } while (static::where('license_key', $key)->exists());

        return $key;
    }
}
