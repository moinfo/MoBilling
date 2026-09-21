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
            'billing_cycle' => $this->billing_cycle,
            'invoice_day_of_month' => $this->invoice_day_of_month,
            'is_active' => $this->is_active,
            'provisioning_type' => $this->provisioning_type,
            'server_id' => $this->server_id,
            'cpanel_package' => $this->cpanel_package,
            'auto_provision' => $this->auto_provision,
            'portal_visible' => $this->portal_visible,
            // Only present on the index listing (withCount/addSelect there);
            // null here just means "not computed for this request", not zero.
            'subscriptions_count' => $this->when(isset($this->subscriptions_count), fn () => (int) $this->subscriptions_count),
            'active_subscriptions_count' => $this->when(isset($this->active_subscriptions_count), fn () => (int) $this->active_subscriptions_count),
            'clients_count' => $this->when(isset($this->clients_count), fn () => (int) $this->clients_count),
            'created_at' => $this->created_at,
        ];
    }
}
