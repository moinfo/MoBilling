<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class PaymentInResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'document_id' => $this->document_id,
            'amount' => $this->amount,
            'payment_date' => $this->payment_date?->format('Y-m-d'),
            'payment_method' => $this->payment_method,
            'reference' => $this->reference,
            'notes' => $this->notes,
            'document' => $this->whenLoaded('document', fn () => [
                'document_number' => $this->document->document_number,
                'type' => $this->document->type,
                'total' => $this->document->total,
                'client' => $this->document->client ? [
                    'name' => $this->document->client->name,
                    'email' => $this->document->client->email,
                ] : null,
            ]),
            'created_at' => $this->created_at,
        ];
    }
}
