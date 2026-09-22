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
            'status' => $this->status,
            'email' => $this->email,
            'phone' => $this->phone,
            // Portal login emails, when different from the client's own —
            // a client's billing email and their portal login(s) commonly
            // differ (an accountant's address, a different day-to-day
            // contact), which otherwise leaves no visible trace anywhere
            // on this list even though search matches against it.
            'portal_emails' => $this->when(
                $this->relationLoaded('portalUsers'),
                fn () => $this->portalUsers->pluck('email')->filter()->unique()->reject(fn ($e) => $e === $this->email)->values()
            ),
            'address' => $this->address,
            'tax_id' => $this->tax_id,
            'first_name' => $this->first_name,
            'last_name' => $this->last_name,
            'company_name' => $this->company_name,
            'address_1' => $this->address_1,
            'address_2' => $this->address_2,
            'city' => $this->city,
            'state' => $this->state,
            'postcode' => $this->postcode,
            'country' => $this->country,
            'active_subscriptions_count' => $this->when(isset($this->active_subscriptions_count), $this->active_subscriptions_count ?? 0),
            'subscription_total' => $this->when(isset($this->subscription_total), round((float) ($this->subscription_total ?? 0), 2)),
            'created_at' => $this->created_at,
        ];
    }
}
