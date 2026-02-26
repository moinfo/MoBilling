<?php

namespace App\Notifications;

use App\Channels\SmsChannel;
use App\Models\Document;
use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use App\Services\PdfService;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class InvoiceTerminationWarningNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    public function __construct(
        public Document $document,
        public Tenant $tenant,
    ) {}

    public function via($notifiable): array
    {
        // Always send via BOTH channels for termination warnings
        $channels = ['mail'];

        if ($this->tenant->sms_enabled) {
            $channels[] = SmsChannel::class;
        }

        return $channels;
    }

    public function toMail($notifiable): MailMessage
    {
        $this->document->loadMissing('items', 'client');
        $currency = $this->tenant->currency;
        $totalFormatted = number_format($this->document->total, 2);

        $pdf = app(PdfService::class)->generate($this->document);
        $pdfContent = $pdf->output();

        $mail = (new MailMessage)
            ->subject("FINAL NOTICE — Service Termination Warning — {$this->document->document_number}")
            ->greeting("Hello {$this->document->client->name},")
            ->line("**This is a final notice regarding invoice {$this->document->document_number}.**")
            ->line("The outstanding amount of {$currency} {$totalFormatted} remains unpaid despite multiple reminders.")
            ->line('**If payment is not received within the next 7 days, your service will be terminated.**')
            ->line('Please settle this invoice immediately to avoid service disruption.')
            ->line("If you have already made payment, please disregard this notice and contact us with your payment reference.")
            ->line('Thank you.')
            ->attachData($pdfContent, "{$this->document->document_number}.pdf", [
                'mime' => 'application/pdf',
            ]);

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toSms($notifiable): ?string
    {
        $currency = $this->tenant->currency;
        $totalFormatted = number_format($this->document->total, 2);

        return "FINAL NOTICE: Invoice {$this->document->document_number} ({$currency} {$totalFormatted}) is unpaid. Service will be TERMINATED in 7 days if not cleared. Pay now. — {$this->tenant->name}";
    }
}
