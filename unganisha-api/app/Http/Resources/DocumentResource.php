<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class DocumentResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'type' => $this->type,
            'document_number' => $this->document_number,
            'client' => new ClientResource($this->whenLoaded('client')),
            // Whitelisted, not the raw model — Tenant carries secrets (pesapal keys, SMTP/WhatsApp
            // credentials) that must never reach the frontend. This is the document's OWN tenant
            // (authoritative), not the viewing user's — the two are almost always the same tenant,
            // but this is what invoice PDFs/emails/WhatsApp sends already source their branding from
            // (PdfService, InvoiceSentNotification), so the client-side "Pay Link" WhatsApp-text
            // builder in DocumentView.tsx should read from here rather than the logged-in user's own
            // (possibly stale/impersonation-edge-case) cached tenant object.
            'tenant' => $this->whenLoaded('tenant', fn () => [
                'name' => $this->tenant->name,
                'currency' => $this->tenant->currency,
                'late_fee_enabled' => $this->tenant->late_fee_enabled,
                'late_fee_percent' => $this->tenant->late_fee_percent,
                'late_fee_days' => $this->tenant->late_fee_days,
                'payment_instructions' => $this->tenant->payment_instructions,
            ]),
            'client_id' => $this->client_id,
            'parent_id' => $this->parent_id,
            'date' => $this->date?->format('Y-m-d'),
            'due_date' => $this->due_date?->format('Y-m-d'),
            'subtotal' => $this->subtotal,
            'discount_amount' => $this->discount_amount,
            'tax_amount' => $this->tax_amount,
            'total' => $this->total,
            'notes' => $this->notes,
            'status' => $this->status,
            'overdue_stage' => $this->overdue_stage,
            'reminder_count' => (int) ($this->reminder_count ?? 0),
            'paid_amount' => $this->paid_amount,
            'balance_due' => $this->balance_due,
            'items' => DocumentItemResource::collection($this->whenLoaded('items')),
            'payments' => PaymentInResource::collection($this->whenLoaded('payments')),
            'refunds' => $this->whenLoaded('refunds', fn () => $this->refunds->map(fn ($r) => [
                'id'          => $r->id,
                'amount'      => (float) $r->amount,
                'method'      => $r->method,
                'reference'   => $r->reference,
                'notes'       => $r->notes,
                'created_at'  => $r->created_at?->toISOString(),
            ])),
            'linked_credit_notes' => $this->whenLoaded('children', fn () => $this->children
                ->where('type', 'credit_note')
                ->map(fn ($c) => [
                    'id'              => $c->id,
                    'document_number' => $c->document_number,
                    'total'           => (float) $c->total,
                    'status'          => $c->status,
                ])->values()),
            'created_by' => $this->created_by,
            'created_at' => $this->created_at,
            'collection_reviewed_by' => $this->collection_reviewed_by,
            'collection_reviewed_by_name' => $this->whenLoaded('collectionReviewedBy', fn () => $this->collectionReviewedBy?->name),
            'collection_reviewed_at' => $this->collection_reviewed_at,
            'collection_review_notes' => $this->collection_review_notes,
        ];
    }
}
