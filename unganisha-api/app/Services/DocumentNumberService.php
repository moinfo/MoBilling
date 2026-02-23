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

        $lastNumber = Document::withoutGlobalScopes()
            ->where('tenant_id', $tenantId)
            ->where('type', $type)
            ->whereYear('created_at', $year)
            ->count();

        $sequence = str_pad($lastNumber + 1, 4, '0', STR_PAD_LEFT);

        return "{$prefix}-{$year}-{$sequence}";
    }
}
