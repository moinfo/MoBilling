<?php

namespace App\Notifications;

use App\Models\Document;
use App\Notifications\Concerns\HasTenantBranding;
use App\Services\PdfService;
use App\Services\ReminderTemplateService;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class InvoiceSentNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    public function __construct(public Document $document) {}

    public function via($notifiable): array
    {
        return ['mail'];
    }

    public function toMail($notifiable): MailMessage
    {
        $this->document->load('items', 'client');
        $this->document->loadMissing(['tenant' => fn ($q) => $q->withoutGlobalScopes()]);

        $tenant = $this->document->tenant;
        $templateService = app(ReminderTemplateService::class);
        $typeName = ucfirst($this->document->type);

        // Subject: use tenant template or default
        $defaultSubject = "{$typeName} {$this->document->document_number} — {$tenant->name}";
        $subject = $tenant->invoice_email_subject
            ? $templateService->renderDocument($tenant->invoice_email_subject, $this->document, $tenant)
            : $defaultSubject;

        // Body: use tenant template or default
        $defaultBody = "Hello {$this->document->client->name},\n\n"
            . "Please find attached your {$typeName}.\n\n"
            . "Amount: {$tenant->currency} " . number_format($this->document->total, 2) . "\n"
            . ($this->document->due_date ? "Due date: {$this->document->due_date->format('d M Y')}\n" : '')
            . "\nThank you for your business.";
        $body = $tenant->invoice_email_body
            ? $templateService->renderDocument($tenant->invoice_email_body, $this->document, $tenant)
            : null;

        $pdf = app(PdfService::class)->generate($this->document);
        $pdfContent = $pdf->output();

        $mail = (new MailMessage)->subject($subject);

        if ($body) {
            // Custom template — render each line
            foreach (explode("\n", $body) as $line) {
                $mail->line($line ?: ' ');
            }
        } else {
            // Default structured email
            $mail->greeting("Hello {$this->document->client->name},")
                ->line("Please find attached your {$typeName}.")
                ->line("Amount: {$tenant->currency} " . number_format($this->document->total, 2));
            if ($this->document->due_date) {
                $mail->line("Due date: {$this->document->due_date->format('d M Y')}");
            }
            $mail->line('Thank you for your business.');
        }

        $this->applyBranding($mail, $tenant);

        return $mail->attachData($pdfContent, "{$this->document->document_number}.pdf", [
            'mime' => 'application/pdf',
        ]);
    }
}
