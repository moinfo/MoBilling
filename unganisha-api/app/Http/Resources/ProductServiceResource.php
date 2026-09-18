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
            'created_at' => $this->created_at,
        ];
    }
}
