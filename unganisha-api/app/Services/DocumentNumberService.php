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
        };

        $year = now()->format('Y');
        $pattern = "{$prefix}-{$year}-";

        $lastNumber = Document::withoutGlobalScopes()
            ->withTrashed()
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
