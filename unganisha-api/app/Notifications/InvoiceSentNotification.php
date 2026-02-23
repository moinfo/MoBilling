<?php

namespace App\Notifications;

use App\Models\Document;
use App\Services\PdfService;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class InvoiceSentNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(public Document $document) {}

    public function via($notifiable): array
    {
        return ['mail'];
    }

    public function toMail($notifiable): MailMessage
    {
        $this->document->load('items', 'client', 'tenant');

        $pdf = app(PdfService::class)->generate($this->document);
        $pdfContent = $pdf->output();

        $typeName = ucfirst($this->document->type);

        return (new MailMessage)
            ->subject("{$typeName} {$this->document->document_number} — {$this->document->tenant->name}")
            ->greeting("Hello {$this->document->client->name},")
            ->line("Please find attached your {$typeName}.")
            ->line("Amount: {$this->document->tenant->currency} " . number_format($this->document->total, 2))
            ->when($this->document->due_date, function ($message) {
                $message->line("Due date: {$this->document->due_date->format('d M Y')}");
            })
            ->line('Thank you for your business.')
            ->attachData($pdfContent, "{$this->document->document_number}.pdf", [
                'mime' => 'application/pdf',
            ]);
    }
}
