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

class InvoiceLateFeeNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    public function __construct(
        public Document $document,
        public Tenant $tenant,
        public float $lateFeeAmount,
        public float $newTotal,
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
        $feeFormatted = number_format($this->lateFeeAmount, 2);
        $newTotalFormatted = number_format($this->newTotal, 2);

        $pdf = app(PdfService::class)->generate($this->document);
        $pdfContent = $pdf->output();

        $mail = (new MailMessage)
            ->subject("Late Fee Applied — {$this->document->document_number} — {$this->tenant->name}")
            ->greeting("Hello {$this->document->client->name},")
            ->line("Invoice {$this->document->document_number} is now overdue.")
            ->line("A 10% late fee of {$currency} {$feeFormatted} has been applied.")
            ->line("**New total: {$currency} {$newTotalFormatted}**")
            ->line('Please settle this invoice promptly to avoid further action.')
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
        $feeFormatted = number_format($this->lateFeeAmount, 2);
        $newTotalFormatted = number_format($this->newTotal, 2);

        return "OVERDUE: Invoice {$this->document->document_number} has a 10% late fee of {$currency} {$feeFormatted} applied. New total: {$currency} {$newTotalFormatted}. Please pay promptly. — {$this->tenant->name}";
    }
}
