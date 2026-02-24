<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class ExpenseCategoryResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'is_active' => $this->is_active,
            'sub_categories' => SubExpenseCategoryResource::collection($this->whenLoaded('subCategories')),
            'created_at' => $this->created_at,
        ];
    }
}
