<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class WorkLocationResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'latitude' => (float) $this->latitude,
            'longitude' => (float) $this->longitude,
            'radius_meters' => $this->radius_meters,
            'is_active' => (bool) $this->is_active,
            'staff_count' => $this->when(
                isset($this->staff_count),
                fn () => (int) $this->staff_count
            ),
            'created_at' => $this->created_at,
        ];
    }
}
