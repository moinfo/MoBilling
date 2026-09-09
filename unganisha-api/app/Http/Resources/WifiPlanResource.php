<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class WifiPlanResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id'                 => $this->id,
            'mikrotik_router_id' => $this->mikrotik_router_id,
            'router'             => $this->when($this->relationLoaded('router') && $this->router, fn () => [
                'id'   => $this->router->id,
                'name' => $this->router->name,
            ]),
            'name'            => $this->name,
            'duration_value'  => $this->duration_value,
            'duration_unit'   => $this->duration_unit,
            'price'           => $this->price,
            'hotspot_profile' => $this->hotspot_profile,
            'is_active'       => (bool) $this->is_active,
            'created_at'      => $this->created_at,
        ];
    }
}
