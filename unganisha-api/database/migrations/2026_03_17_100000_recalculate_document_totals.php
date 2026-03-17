<?php

use Illuminate\Database\Migrations\Migration;
use App\Models\Document;

return new class extends Migration
{
    public function up(): void
    {
        Document::withoutGlobalScopes()->with('items')->chunk(100, function ($documents) {
            foreach ($documents as $doc) {
                if ($doc->items->isEmpty()) {
                    continue;
                }

                $subtotal = 0;
                $discountTotal = 0;
                $taxAmount = 0;

                foreach ($doc->items as $item) {
                    $lineBase = $item->quantity * $item->price;
                    $lineDiscount = $item->discount_type === 'flat'
                        ? min($item->discount_value, $lineBase)
                        : $lineBase * ($item->discount_value / 100);
                    $lineAfterDiscount = $lineBase - $lineDiscount;
                    $lineTax = $lineAfterDiscount * (($item->tax_percent ?? 0) / 100);

                    $subtotal += $lineBase;
                    $discountTotal += $lineDiscount;
                    $taxAmount += $lineTax;
                }

                $total = round($subtotal - $discountTotal + $taxAmount, 2);

                if (
                    abs((float) $doc->subtotal - round($subtotal, 2)) > 0.01 ||
                    abs((float) $doc->total - $total) > 0.01
                ) {
                    $doc->updateQuietly([
                        'subtotal' => round($subtotal, 2),
                        'discount_amount' => round($discountTotal, 2),
                        'tax_amount' => round($taxAmount, 2),
                        'total' => $total,
                    ]);
                }
            }
        });
    }

    public function down(): void
    {
        // Cannot reverse — previous totals are unknown
    }
};
