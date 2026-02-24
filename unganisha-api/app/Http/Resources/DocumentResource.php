<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class DocumentResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'type' => $this->type,
            'document_number' => $this->document_number,
            'client' => new ClientResource($this->whenLoaded('client')),
            'client_id' => $this->client_id,
            'parent_id' => $this->parent_id,
            'date' => $this->date?->format('Y-m-d'),
            'due_date' => $this->due_date?->format('Y-m-d'),
            'subtotal' => $this->subtotal,
            'discount_amount' => $this->discount_amount,
            'tax_amount' => $this->tax_amount,
            'total' => $this->total,
            'notes' => $this->notes,
            'status' => $this->status,
            'paid_amount' => $this->paid_amount,
            'balance_due' => $this->balance_due,
            'items' => DocumentItemResource::collection($this->whenLoaded('items')),
            'payments' => PaymentInResource::collection($this->whenLoaded('payments')),
            'created_by' => $this->created_by,
            'created_at' => $this->created_at,
        ];
    }
}
