<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class PaymentOutResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'bill_id' => $this->bill_id,
            'amount' => $this->amount,
            'payment_date' => $this->payment_date?->format('Y-m-d'),
            'payment_method' => $this->payment_method,
            'control_number' => $this->control_number,
            'reference' => $this->reference,
            'notes' => $this->notes,
            'receipt_url' => $this->receipt_path ? asset('storage/' . $this->receipt_path) : null,
            'bill' => new BillResource($this->whenLoaded('bill')),
            'created_at' => $this->created_at,
        ];
    }
}
