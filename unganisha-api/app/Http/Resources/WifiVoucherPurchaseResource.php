<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class WifiVoucherPurchaseResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id'                 => $this->id,
            'router'             => $this->when($this->relationLoaded('router') && $this->router, fn () => [
                'id' => $this->router->id, 'name' => $this->router->name,
            ]),
            'plan'               => $this->when($this->relationLoaded('plan') && $this->plan, fn () => [
                'id' => $this->plan->id, 'name' => $this->plan->name,
            ]),
            'customer_phone'     => $this->customer_phone,
            'customer_name'      => $this->customer_name,
            'amount'             => $this->amount,
            'status'             => $this->status,
            'hotspot_username'   => $this->hotspot_username,
            'hotspot_password'   => $this->hotspot_password,
            'voucher_expires_at' => $this->voucher_expires_at,
            'completed_at'       => $this->completed_at,
            'created_at'         => $this->created_at,
        ];
    }
}
