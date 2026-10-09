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
            // Shown in cleartext on purpose — the assigned staff needs it to
            // actually log in and check the system. Never exposed outside
            // the admin list/detail and the assigned staff's own "mine" list.
            'login_username' => $this->login_username,
            'login_password' => $this->login_password,
            // This system's own check-in window — not the tenant's.
            'window_from' => $this->window_from,
            'window_to' => $this->window_to,
            // Resolved (never null) — a system created before this setting
            // existed still reports all four, via requiredFields()'s default.
            'required_fields' => $this->requiredFields(),
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
                'cash' => $this->todaysReport->cash,
                'sales' => $this->todaysReport->sales,
                'credit' => $this->todaysReport->credit,
                'gain_loss' => $this->todaysReport->gain_loss,
                'custom_values' => $this->todaysReport->custom_values ?? [],
                'submitted_on_time' => $this->todaysReport->submitted_on_time,
                'submitted_at' => $this->todaysReport->created_at,
            ]),
            'created_at' => $this->created_at,
        ];
    }
}
