<?php

namespace App\Services;

use App\Models\Document;
use Barryvdh\DomPDF\Facade\Pdf;

class PdfService
{
    public function generate(Document $document)
    {
        $document->load('items', 'client', 'tenant');

        return Pdf::loadView('pdf.document', [
            'document' => $document,
            'tenant' => $document->tenant,
            'client' => $document->client,
            'items' => $document->items,
        ])->setPaper('a4');
    }
}
