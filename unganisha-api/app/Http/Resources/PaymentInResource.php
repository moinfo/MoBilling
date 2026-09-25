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
            'client_id' => $this->client_id,
            'document_id' => $this->document_id,
            'amount' => $this->amount,
            'payment_date' => $this->payment_date?->format('Y-m-d'),
            'payment_method' => $this->payment_method,
            'reference' => $this->reference,
            'notes' => $this->notes,
            // Proofs recorded via Receive Payments live on the private disk (served by an authenticated endpoint).
            'attachment_url' => $this->attachment_path && !str_starts_with($this->attachment_path, 'payment-proofs/')
                ? url('storage/' . $this->attachment_path)
                : null,
            'has_private_proof' => (bool) ($this->attachment_path && str_starts_with($this->attachment_path, 'payment-proofs/')),
            'client' => $this->whenLoaded('client', fn () => [
                'name' => $this->client->name,
                'email' => $this->client->email,
            ]),
            'received_by' => $this->whenLoaded('receiver', fn () => $this->receiver ? [
                'id' => $this->receiver->id,
                'name' => $this->receiver->name,
            ] : null),
            'document' => $this->whenLoaded('document', fn () => $this->document ? [
                'document_number' => $this->document->document_number,
                'type' => $this->document->type,
                'total' => $this->document->total,
                'client' => $this->document->client ? [
                    'name' => $this->document->client->name,
                    'email' => $this->document->client->email,
                ] : null,
            ] : null),
            'created_at' => $this->created_at,
        ];
    }
}
