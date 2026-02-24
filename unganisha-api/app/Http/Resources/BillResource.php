<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class BillResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'statutory_id' => $this->statutory_id,
            'name' => $this->name,
            'category' => $this->category,
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
            'issue_date' => $this->issue_date?->format('Y-m-d'),
            'amount' => $this->amount,
            'cycle' => $this->cycle,
            'due_date' => $this->due_date?->format('Y-m-d'),
            'remind_days_before' => $this->remind_days_before,
            'is_active' => $this->is_active,
            'paid_at' => $this->paid_at?->toISOString(),
            'notes' => $this->notes,
            'is_overdue' => !$this->paid_at && $this->due_date?->isPast(),
            'payments' => PaymentOutResource::collection($this->whenLoaded('payments')),
            'created_at' => $this->created_at,
        ];
    }
}
