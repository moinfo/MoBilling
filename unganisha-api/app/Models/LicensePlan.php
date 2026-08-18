<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** Pricing catalog for self-hosted licenses — see the create_license_plans_table migration for why this is separate from SubscriptionPlan. */
class LicensePlan extends Model
{
    use HasUuids;

    protected $fillable = [
        'product', 'name', 'description',
        'monthly_price', 'quarterly_price', 'semi_annual_price', 'annual_price', 'perpetual_price',
        'is_active',
    ];

    protected $casts = [
        'monthly_price' => 'decimal:2',
        'quarterly_price' => 'decimal:2',
        'semi_annual_price' => 'decimal:2',
        'annual_price' => 'decimal:2',
        'perpetual_price' => 'decimal:2',
        'is_active' => 'boolean',
    ];

    public function priceFor(string $billingPeriod): ?float
    {
        $column = match ($billingPeriod) {
            'monthly' => 'monthly_price',
            'quarterly' => 'quarterly_price',
            'semi_annual' => 'semi_annual_price',
            'annual' => 'annual_price',
            'perpetual' => 'perpetual_price',
            default => null,
        };

        if ($column === null || $this->$column === null) {
            return null;
        }

        return (float) $this->$column;
    }
}
