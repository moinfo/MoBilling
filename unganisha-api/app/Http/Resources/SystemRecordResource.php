<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class SystemRecordResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'system_id' => $this->system_id,
            'system' => $this->when($this->relationLoaded('system') && $this->system, fn () => [
                'id' => $this->system->id,
                'name' => $this->system->name,
            ]),
            'system_property_id' => $this->system_property_id,
            'system_property' => $this->when($this->relationLoaded('systemProperty') && $this->systemProperty, fn () => [
                'id' => $this->systemProperty->id,
                'name' => $this->systemProperty->name,
            ]),
            'bank_account_id' => $this->bank_account_id,
            'bank_account' => $this->when($this->relationLoaded('bankAccount') && $this->bankAccount, fn () => [
                'id' => $this->bankAccount->id,
                'bank_name' => $this->bankAccount->bank_name,
                'account_number' => $this->bankAccount->account_number,
            ]),
            'record_date' => $this->record_date?->format('Y-m-d'),
            'amount' => $this->amount,
            'notes' => $this->notes,
            'receipt_attachment_url' => $this->receipt_attachment_path
                ? asset('storage/' . $this->receipt_attachment_path)
                : null,
            'created_by' => $this->when($this->relationLoaded('createdBy') && $this->createdBy, fn () => [
                'id' => $this->createdBy->id,
                'name' => $this->createdBy->name,
            ]),
            'created_at' => $this->created_at,
        ];
    }
}
