<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class ProductServiceResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'type' => $this->type,
            'name' => $this->name,
            'code' => $this->code,
            'description' => $this->description,
            'price' => $this->price,
            'tax_percent' => $this->tax_percent,
            'unit' => $this->unit,
            'category' => $this->category,
            'is_active' => $this->is_active,
            'created_at' => $this->created_at,
        ];
    }
}
