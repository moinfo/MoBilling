<?php

namespace App\Services;

use App\Models\Document;

class DocumentNumberService
{
    public function generate(string $type, string $tenantId): string
    {
        $prefix = match ($type) {
            'quotation' => 'QUO',
            'proforma' => 'PRO',
            'invoice' => 'INV',
            'credit_note' => 'CN',
            default => throw new \InvalidArgumentException("Unsupported document type: {$type}"),
        };

        $year = now()->format('Y');
        $pattern = "{$prefix}-{$year}-";

        // Sequence is per-tenant: each tenant has its own QUO/PRO/INV series.
        // (The documents table enforces a composite unique on [tenant_id, document_number].)
        $lastNumber = Document::withoutGlobalScopes()
            ->withTrashed()
            ->where('tenant_id', $tenantId)
            ->where('document_number', 'LIKE', "{$pattern}%")
            ->orderByDesc('document_number')
            ->value('document_number');

        $sequence = 1;
        if ($lastNumber) {
            $lastSeq = (int) substr($lastNumber, strlen($pattern));
            $sequence = $lastSeq + 1;
        }

        return $pattern . str_pad($sequence, 4, '0', STR_PAD_LEFT);
    }
}
