<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class ClientSubscriptionResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'client_id' => $this->client_id,
            'client_name' => $this->whenLoaded('client', fn () => $this->client->name),
            'product_service_id' => $this->product_service_id,
            'product_service_name' => $this->whenLoaded('productService', fn () => $this->productService->name),
            'billing_cycle' => $this->whenLoaded('productService', fn () => $this->productService->billing_cycle),
            'price' => $this->whenLoaded('productService', fn () => $this->productService->price),
            'label' => $this->label,
            'quantity' => $this->quantity,
            'start_date' => $this->start_date?->format('Y-m-d'),
            'status' => $this->status,
            'metadata' => $this->metadata,
            'created_at' => $this->created_at,
        ];
    }
}
