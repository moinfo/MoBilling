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
            'discount_type' => $this->discount_type,
            'discount_value' => $this->discount_value,
            'start_date' => $this->start_date?->format('Y-m-d'),
            'expire_date' => $this->expire_date?->format('Y-m-d'),
            'status' => $this->status,
            'metadata' => $this->metadata,
            'recurring_amount' => $this->recurring_amount,
            'linode_server' => $this->whenLoaded('linodeResource', fn () => $this->linodeResource ? [
                'id' => $this->linodeResource->id, 'label' => $this->linodeResource->label,
                'ipv4' => $this->linodeResource->ipv4 ?? [], 'region' => $this->linodeResource->region,
                'plan' => $this->linodeResource->plan, 'status' => $this->linodeResource->status,
            ] : null),
            'created_at' => $this->created_at,
        ];
    }
}
