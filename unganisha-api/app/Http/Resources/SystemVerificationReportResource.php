<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class SystemVerificationReportResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'system_verification_id' => $this->system_verification_id,
            'system' => $this->when($this->relationLoaded('systemVerification') && $this->systemVerification, fn () => [
                'id' => $this->systemVerification->id,
                'name' => $this->systemVerification->name,
                'domain_name' => $this->systemVerification->domain_name,
            ]),
            'user_id' => $this->user_id,
            'user' => $this->when($this->relationLoaded('user') && $this->user, fn () => [
                'id' => $this->user->id,
                'name' => $this->user->name,
            ]),
            'report_date' => $this->report_date?->format('Y-m-d'),
            'status' => $this->status,
            'notes' => $this->notes,
            'created_at' => $this->created_at,
        ];
    }
}
