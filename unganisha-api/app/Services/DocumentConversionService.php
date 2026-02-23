<?php

namespace App\Services;

use App\Models\Document;

class DocumentConversionService
{
    public function convert(Document $document, string $targetType): Document
    {
        $allowedConversions = [
            'quotation' => 'proforma',
            'proforma' => 'invoice',
        ];

        if (($allowedConversions[$document->type] ?? null) !== $targetType) {
            throw new \Exception("Cannot convert {$document->type} to {$targetType}");
        }

        $newDocument = $document->replicate();
        $newDocument->type = $targetType;
        $newDocument->parent_id = $document->id;
        $newDocument->status = 'draft';
        $newDocument->document_number = app(DocumentNumberService::class)
            ->generate($targetType, $document->tenant_id);
        $newDocument->date = now();
        $newDocument->save();

        foreach ($document->items as $item) {
            $newItem = $item->replicate();
            $newItem->document_id = $newDocument->id;
            $newItem->save();
        }

        $document->update(['status' => 'accepted']);

        return $newDocument->load('items', 'client');
    }
}
