<?php

namespace App\Services;

use App\Models\Coupon;
use App\Models\CouponRedemption;
use App\Models\ProductService;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Coupon validation + redemption. All discount amounts are computed here from
 * the persisted coupon — a client-sent discount is never trusted.
 */
class CouponService
{
    /**
     * Validate a coupon code for an order and compute the server-side discount.
     *
     * @return array{coupon: ?Coupon, discount: float, error: ?string}
     */
    public function validateForOrder(
        string $code,
        string $tenantId,
        ProductService $product,
        float $orderBase,
        ?string $clientId = null
    ): array {
        $code = strtoupper(trim($code));

        $coupon = Coupon::withoutGlobalScopes()
            ->where('tenant_id', $tenantId)
            ->where('code', $code)
            ->first();

        // Unknown code is indistinguishable across tenants (tenant scoping).
        if (!$coupon) {
            return ['coupon' => null, 'discount' => 0.0, 'error' => 'This promo code is not valid.'];
        }

        $now = Carbon::now();

        if (!$coupon->is_active) {
            return ['coupon' => $coupon, 'discount' => 0.0, 'error' => 'This promo code is no longer active.'];
        }
        if ($coupon->starts_at && $now->lt($coupon->starts_at)) {
            return ['coupon' => $coupon, 'discount' => 0.0, 'error' => 'This promo code is not active yet.'];
        }
        if ($coupon->expires_at && $now->gt($coupon->expires_at)) {
            return ['coupon' => $coupon, 'discount' => 0.0, 'error' => 'This promo code has expired.'];
        }
        if ($coupon->max_uses !== null && $coupon->uses >= $coupon->max_uses) {
            return ['coupon' => $coupon, 'discount' => 0.0, 'error' => 'This promo code has reached its usage limit.'];
        }
        if (!$coupon->appliesToProduct($product)) {
            return ['coupon' => $coupon, 'discount' => 0.0, 'error' => 'This promo code does not apply to this product.'];
        }
        if ($coupon->min_order !== null && $orderBase < (float) $coupon->min_order) {
            return [
                'coupon'   => $coupon,
                'discount' => 0.0,
                'error'    => 'Your order does not meet the minimum for this promo code.',
            ];
        }

        $discount = $coupon->discountFor($orderBase, $product);

        if ($discount <= 0) {
            return ['coupon' => $coupon, 'discount' => 0.0, 'error' => 'This promo code does not apply to this product.'];
        }

        return ['coupon' => $coupon, 'discount' => $discount, 'error' => null];
    }

    /**
     * Atomically consume one use of the coupon and record the redemption.
     * Must be called inside a DB transaction. The conditional UPDATE guards
     * against concurrent orders pushing uses past max_uses.
     *
     * @return bool True if the use was consumed; false if it just hit the cap.
     */
    public function redeem(Coupon $coupon, string $clientId, ?string $documentId, float $discount): bool
    {
        $query = Coupon::withoutGlobalScopes()->whereKey($coupon->id);

        // Only increment while under the cap (unlimited when max_uses is null).
        if ($coupon->max_uses !== null) {
            $query->whereColumn('uses', '<', 'max_uses');
        }

        $consumed = $query->update(['uses' => DB::raw('uses + 1')]);

        if ($consumed === 0) {
            return false; // raced past the limit — caller should reject the coupon
        }

        CouponRedemption::withoutGlobalScopes()->create([
            'tenant_id'       => $coupon->tenant_id,
            'coupon_id'       => $coupon->id,
            'client_id'       => $clientId,
            'document_id'     => $documentId,
            'discount_amount' => round($discount, 2),
        ]);

        return true;
    }
}
