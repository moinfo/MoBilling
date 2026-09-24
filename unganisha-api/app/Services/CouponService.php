<?php

namespace App\Services;

use App\Models\Coupon;
use App\Models\CouponRedemption;
use App\Models\Document;
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
        if ($coupon->max_uses_per_client !== null && $clientId
            && $this->clientUses($coupon, $clientId) >= $coupon->max_uses_per_client) {
            return ['coupon' => $coupon, 'discount' => 0.0, 'error' => 'You have already used this promo code the maximum number of times.'];
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
     * Live (non-released) order redemptions of this coupon by one client.
     * Renewal discounts of recurring coupons are audit rows, not extra uses.
     */
    public function clientUses(Coupon $coupon, string $clientId): int
    {
        return CouponRedemption::withoutGlobalScopes()
            ->where('coupon_id', $coupon->id)
            ->where('client_id', $clientId)
            ->whereNull('released_at')
            ->where(fn ($q) => $q->whereNull('document_id')->orWhereNotIn('document_id',
                Document::withoutGlobalScopes()->where('notes', 'like', 'Auto-generated recurring invoice%')->select('id')))
            ->count();
    }

    /**
     * Give back the use(s) held by an unpaid order that was cancelled/expired.
     * Idempotent: a redemption is released once (released_at). Only the order
     * redemption decrements coupons.uses (recurring renewal rows never did).
     * A paid document is never released.
     */
    public function releaseForDocument(Document $document): int
    {
        if ($document->status === 'paid') {
            return 0;
        }
        $isRenewal = str_starts_with((string) $document->notes, 'Auto-generated recurring invoice');
        $released = 0;

        DB::transaction(function () use ($document, $isRenewal, &$released) {
            $rows = CouponRedemption::withoutGlobalScopes()
                ->where('document_id', $document->id)->whereNull('released_at')
                ->lockForUpdate()->get();
            foreach ($rows as $row) {
                $row->update(['released_at' => now()]);
                if (!$isRenewal) {
                    Coupon::withoutGlobalScopes()->whereKey($row->coupon_id)->where('uses', '>', 0)
                        ->update(['uses' => DB::raw('uses - 1')]);
                }
                $released++;
            }
        });

        return $released;
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
        if ($coupon->max_uses_per_client !== null && $this->clientUses($coupon, $clientId) >= $coupon->max_uses_per_client) {
            return false;
        }

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
