<?php

namespace App\Services;

use App\Models\Bill;
use App\Models\Document;
use App\Models\Tenant;

class ReminderTemplateService
{
    /**
     * Replace placeholders in a bill reminder template.
     *
     * Supported: {bill_name}, {amount}, {currency}, {due_date}, {company_name}
     */
    public function render(string $template, Bill $bill, Tenant $tenant): string
    {
        return str_replace(
            ['{bill_name}', '{amount}', '{currency}', '{due_date}', '{company_name}'],
            [
                $bill->name,
                number_format($bill->amount, 2),
                $tenant->currency,
                $bill->due_date->format('d M Y'),
                $tenant->name,
            ],
            $template
        );
    }

    /**
     * Replace placeholders in a document (invoice/quote) template.
     *
     * Supported: {doc_type}, {doc_number}, {client_name}, {amount}, {currency}, {due_date}, {company_name}
     */
    public function renderDocument(string $template, Document $document, Tenant $tenant): string
    {
        return str_replace(
            ['{doc_type}', '{doc_number}', '{client_name}', '{amount}', '{currency}', '{due_date}', '{company_name}'],
            [
                ucfirst($document->type),
                $document->document_number,
                $document->client->name ?? '',
                number_format($document->total, 2),
                $tenant->currency,
                $document->due_date ? $document->due_date->format('d M Y') : 'N/A',
                $tenant->name,
            ],
            $template
        );
    }
}
