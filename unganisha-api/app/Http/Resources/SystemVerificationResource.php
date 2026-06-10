<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class SystemVerificationResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'domain_name' => $this->domain_name,
            'client_id' => $this->client_id,
            'client' => $this->when($this->relationLoaded('client') && $this->client, fn () => [
                'id' => $this->client->id,
                'name' => $this->client->name,
                'email' => $this->client->email,
            ]),
            'is_active' => (bool) $this->is_active,
            'assigned_user_id' => $this->assigned_user_id,
            'assigned_user' => $this->when($this->relationLoaded('assignedUser') && $this->assignedUser, fn () => [
                'id' => $this->assignedUser->id,
                'name' => $this->assignedUser->name,
            ]),
            // "is today's check-in done?" — boolean shortcut + the actual report id/status if so.
            'todays_report' => $this->when($this->relationLoaded('todaysReport') && $this->todaysReport, fn () => [
                'id' => $this->todaysReport->id,
                'status' => $this->todaysReport->status,
                'notes' => $this->todaysReport->notes,
                'submitted_at' => $this->todaysReport->created_at,
            ]),
            'created_at' => $this->created_at,
        ];
    }
}
