<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class SystemRecordExpenseResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'system_record_id' => $this->system_record_id,
            'system_record' => $this->when($this->relationLoaded('systemRecord') && $this->systemRecord, fn () => [
                'id' => $this->systemRecord->id,
                'amount' => $this->systemRecord->amount,
                'record_date' => $this->systemRecord->record_date?->format('Y-m-d'),
                'transaction_reference' => $this->systemRecord->transaction_reference,
                'system' => $this->systemRecord->relationLoaded('system') && $this->systemRecord->system
                    ? ['id' => $this->systemRecord->system->id, 'name' => $this->systemRecord->system->name]
                    : null,
                'system_property' => $this->systemRecord->relationLoaded('systemProperty') && $this->systemRecord->systemProperty
                    ? ['id' => $this->systemRecord->systemProperty->id, 'name' => $this->systemRecord->systemProperty->name]
                    : null,
            ]),
            'amount' => $this->amount,
            'expense_date' => $this->expense_date?->format('Y-m-d'),
            'description' => $this->description,
            'attachment_url' => $this->attachment_path ? asset('storage/' . $this->attachment_path) : null,
            'created_by' => $this->when($this->relationLoaded('createdBy') && $this->createdBy, fn () => [
                'id' => $this->createdBy->id,
                'name' => $this->createdBy->name,
            ]),
            'created_at' => $this->created_at,
        ];
    }
}
