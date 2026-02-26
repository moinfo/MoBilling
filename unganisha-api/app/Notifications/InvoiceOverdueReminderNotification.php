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

class InvoiceOverdueReminderNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    public function __construct(
        public Document $document,
        public Tenant $tenant,
        public int $daysOverdue,
    ) {}

    public function via($notifiable): array
    {
        $channels = ['mail'];

        if ($this->tenant->sms_enabled && $this->tenant->reminder_sms_enabled) {
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
            ->subject("Payment Overdue — {$this->document->document_number} — {$this->tenant->name}")
            ->greeting("Hello {$this->document->client->name},")
            ->line("This is a reminder that invoice {$this->document->document_number} for {$currency} {$totalFormatted} is now {$this->daysOverdue} day(s) overdue.")
            ->line('Please make payment as soon as possible to avoid service disruption.')
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

        return "OVERDUE: Invoice {$this->document->document_number} for {$currency} {$totalFormatted} is {$this->daysOverdue} days overdue. Please pay immediately. — {$this->tenant->name}";
    }
}
