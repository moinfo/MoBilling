<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class UserResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $roleRelation = $this->getRelationValue('role');

        return [
            'id' => $this->id,
            'name' => $this->name,
            'email' => $this->email,
            'phone' => $this->phone,
            'role' => $this->getAttributeValue('role'),
            'role_id' => $this->role_id,
            'role_name' => $roleRelation?->label,
            'is_active' => $this->is_active,
            'created_at' => $this->created_at,
        ];
    }
}
