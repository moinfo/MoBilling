<?php

namespace App\Services;

use App\Models\Document;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class DocumentConversionService
{
    public function convert(Document $document, string $targetType): Document
    {
        $allowedConversions = [
            'quotation' => 'proforma',
            'proforma' => 'invoice',
        ];

        if (($allowedConversions[$document->type] ?? null) !== $targetType) {
            throw ValidationException::withMessages([
                'target_type' => "Cannot convert a {$document->type} to a {$targetType}.",
            ]);
        }

        if (in_array($document->status, ['cancelled', 'rejected'], true)) {
            throw ValidationException::withMessages([
                'target_type' => "A {$document->status} {$document->type} cannot be converted.",
            ]);
        }

        // Prevent double-conversion: a source that already produced a child of this
        // target type must not be converted again (which would duplicate the invoice).
        if ($document->children()->where('type', $targetType)->exists()) {
            throw ValidationException::withMessages([
                'target_type' => "This {$document->type} has already been converted to a {$targetType}.",
            ]);
        }

        return DB::transaction(function () use ($document, $targetType) {
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
        });
    }
}
