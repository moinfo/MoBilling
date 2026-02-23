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
            'name' => $this->name,
            'category' => $this->category,
            'amount' => $this->amount,
            'cycle' => $this->cycle,
            'due_date' => $this->due_date?->format('Y-m-d'),
            'remind_days_before' => $this->remind_days_before,
            'is_active' => $this->is_active,
            'notes' => $this->notes,
            'next_due_date' => $this->next_due_date?->format('Y-m-d'),
            'is_overdue' => $this->due_date?->isPast(),
            'payments' => PaymentOutResource::collection($this->whenLoaded('payments')),
            'created_at' => $this->created_at,
        ];
    }
}
