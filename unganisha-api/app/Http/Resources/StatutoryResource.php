<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class StatutoryResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $currentBill = $this->whenLoaded('currentBill', fn() => $this->currentBill);
        $paidAmount = 0;
        if ($currentBill && $currentBill->relationLoaded('payments')) {
            $paidAmount = $currentBill->payments->sum('amount');
        }

        $amount = (float) $this->amount;
        $daysRemaining = now()->startOfDay()->diffInDays($this->next_due_date, false);

        // Compute status based on current bill state
        $status = 'upcoming';
        if ($currentBill && $currentBill->paid_at) {
            $status = 'paid';
        } elseif ($daysRemaining < 0) {
            $status = 'overdue';
        } elseif ($daysRemaining <= $this->remind_days_before) {
            $status = 'due_soon';
        }

        return [
            'id' => $this->id,
            'name' => $this->name,
            'bill_category_id' => $this->bill_category_id,
            'bill_category' => $this->whenLoaded('billCategory', function () {
                if (!$this->billCategory) {
                    return null;
                }
                return [
                    'id' => $this->billCategory->id,
                    'name' => $this->billCategory->name,
                    'parent_name' => $this->billCategory->parent?->name,
                ];
            }),
            'amount' => $this->amount,
            'cycle' => $this->cycle,
            'issue_date' => $this->issue_date?->format('Y-m-d'),
            'next_due_date' => $this->next_due_date?->format('Y-m-d'),
            'remind_days_before' => $this->remind_days_before,
            'is_active' => $this->is_active,
            'notes' => $this->notes,
            'created_at' => $this->created_at,

            // Computed schedule fields
            'status' => $status,
            'days_remaining' => (int) $daysRemaining,
            'paid_amount' => round($paidAmount, 2),
            'remaining_amount' => round($amount - $paidAmount, 2),
            'progress_percent' => $amount > 0 ? round(($paidAmount / $amount) * 100, 1) : 0,
            'current_bill' => $this->whenLoaded('currentBill', function () {
                return $this->currentBill ? new BillResource($this->currentBill) : null;
            }),
        ];
    }
}
