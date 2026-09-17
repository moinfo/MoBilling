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
            'work_location_id' => $this->work_location_id,
            'work_location_name' => $this->getRelationValue('workLocation')?->name,
            'attendance_device_model' => $this->attendance_device_model,
            'attendance_device_bound_at' => $this->attendance_device_bound_at,
            'created_at' => $this->created_at,
        ];
    }
}
