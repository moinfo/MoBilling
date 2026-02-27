<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class ClientResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'email' => $this->email,
            'phone' => $this->phone,
            'address' => $this->address,
            'tax_id' => $this->tax_id,
            'active_subscriptions_count' => $this->when(isset($this->active_subscriptions_count), $this->active_subscriptions_count ?? 0),
            'subscription_total' => $this->when(isset($this->subscription_total), round((float) ($this->subscription_total ?? 0), 2)),
            'created_at' => $this->created_at,
        ];
    }
}
