<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Carbon\Carbon;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Promotion / coupon code (WHMCS-parity). A percent or fixed discount applied
 * at order time. All discount amounts are computed server-side from this model
 * — never trust a client-sent discount.
 */
class Coupon extends Model
{
    use HasFactory, HasUuids, SoftDeletes, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'code', 'description', 'type', 'value', 'applies_to',
        'max_uses', 'uses', 'min_order', 'starts_at', 'expires_at',
        'recurring', 'is_active',
    ];

    protected $casts = [
        'value'      => 'decimal:2',
        'min_order'  => 'decimal:2',
        'max_uses'   => 'integer',
        'uses'       => 'integer',
        'starts_at'  => 'datetime',
        'expires_at' => 'datetime',
        'recurring'  => 'boolean',
        'is_active'  => 'boolean',
    ];

    /** Always store the code upper-cased so lookups are case-insensitive. */
    public function setCodeAttribute($value): void
    {
        $this->attributes['code'] = strtoupper(trim((string) $value));
    }

    public function products()
    {
        return $this->belongsToMany(
            ProductService::class,
            'coupon_products',
            'coupon_id',
            'product_service_id'
        );
    }

    public function redemptions()
    {
        return $this->hasMany(CouponRedemption::class);
    }

    public function scopeActive($query)
    {
        return $query->where('is_active', true);
    }

    /** Whether the coupon is currently within its active window and usable. */
    public function isRedeemable(?Carbon $at = null): bool
    {
        $at ??= Carbon::now();

        if (!$this->is_active) {
            return false;
        }
        if ($this->starts_at && $at->lt($this->starts_at)) {
            return false;
        }
        if ($this->expires_at && $at->gt($this->expires_at)) {
            return false;
        }
        if ($this->max_uses !== null && $this->uses >= $this->max_uses) {
            return false;
        }

        return true;
    }

    /** Whether this coupon is allowed to discount the given product. */
    public function appliesToProduct(ProductService $product): bool
    {
        if ($this->applies_to === 'all') {
            return true;
        }

        return $this->products()
            ->where('product_services.id', $product->id)
            ->exists();
    }

    /**
     * Discount amount (in currency) for a given taxable base and product,
     * honoring type / applies_to / min_order. Fixed discounts are capped at
     * the base so a total can never go negative. Returns 0 when not eligible.
     */
    public function discountFor(float $base, ProductService $product): float
    {
        if ($base <= 0) {
            return 0.0;
        }
        if (!$this->appliesToProduct($product)) {
            return 0.0;
        }
        if ($this->min_order !== null && $base < (float) $this->min_order) {
            return 0.0;
        }

        $discount = $this->type === 'percent'
            ? $base * ((float) $this->value / 100)
            : (float) $this->value;

        $discount = min($discount, $base); // never exceed the base

        return round(max($discount, 0), 2);
    }
}
