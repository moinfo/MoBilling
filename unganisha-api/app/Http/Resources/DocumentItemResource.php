<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class DocumentItemResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'product_service_id' => $this->product_service_id,
            'item_type' => $this->item_type,
            'description' => $this->description,
            'quantity' => $this->quantity,
            'price' => $this->price,
            'discount_type' => $this->discount_type,
            'discount_value' => $this->discount_value,
            'tax_percent' => $this->tax_percent,
            'tax_amount' => $this->tax_amount,
            'total' => $this->total,
            'unit' => $this->unit,
        ];
    }
}
