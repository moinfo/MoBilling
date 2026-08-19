<?php

namespace App\Models;

use Carbon\Carbon;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class License extends Model
{
    use HasUuids;

    protected $fillable = [
        'license_key', 'customer_name', 'customer_email', 'product',
        'domain', 'billing_period', 'starts_at', 'amount_paid', 'status', 'expires_at', 'last_validated_at', 'notes',
    ];

    protected $casts = [
        'starts_at' => 'date',
        'expires_at' => 'date',
        'last_validated_at' => 'datetime',
        'amount_paid' => 'decimal:2',
    ];

    private const PERIOD_MONTHS = [
        'monthly' => 1,
        'quarterly' => 3,
        'semi_annual' => 6,
        'annual' => 12,
    ];

    /** null for 'perpetual' (no expiry) — otherwise starts_at + the period's month count. */
    public static function calculateExpiry(string $startsAt, string $billingPeriod): ?Carbon
    {
        if ($billingPeriod === 'perpetual') {
            return null;
        }

        $months = self::PERIOD_MONTHS[$billingPeriod] ?? null;
        if ($months === null) {
            throw new \InvalidArgumentException("Unknown billing period: {$billingPeriod}");
        }

        return Carbon::parse($startsAt)->addMonths($months);
    }

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
