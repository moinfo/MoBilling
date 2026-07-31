<?php

namespace App\Notifications;

use App\Channels\SmsChannel;
use App\Channels\WhatsAppChannel;
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
        $channels = [];

        if ($this->tenant->email_enabled && $notifiable->email) {
            $channels[] = 'mail';
        }

        if ($this->tenant->sms_enabled && $this->tenant->reminder_sms_enabled) {
            $channels[] = SmsChannel::class;
        }

        if ($this->tenant->whatsapp_enabled && $this->tenant->reminder_whatsapp_enabled) {
            $channels[] = WhatsAppChannel::class;
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
            ->line('Please settle this invoice promptly to avoid further action.');

        if ($this->tenant->pesapal_enabled && $this->document->balance_due > 0) {
            $payUrl = $this->tenantPortalUrl($this->document->tenant, "/pay/{$this->document->id}");
            $mail->action('Pay Now', $payUrl);
        }

        $mail->line('Thank you.')
            ->attachData($pdfContent, "{$this->document->document_number}.pdf", [
                'mime' => 'application/pdf',
            ]);

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toWhatsApp($notifiable): array
    {
        $currency = $this->tenant->currency;
        $payLine = ($this->tenant->pesapal_enabled && $this->document->balance_due > 0)
            ? 'Pay online at ' . $this->tenantPortalUrl($this->document->tenant, "/pay/{$this->document->id}")
            : 'Contact us for payment options';

        return [
            'template' => 'late_fee_notice_v1',
            'parameters' => [
                $this->document->document_number,
                "{$currency} " . number_format($this->lateFeeAmount, 2),
                "{$currency} " . number_format($this->newTotal, 2),
                $payLine,
                $this->tenant->name,
            ],
            'language' => 'en',
            'fallback' => "⚠️ Late fee {$currency} " . number_format($this->lateFeeAmount, 2) . " applied to invoice {$this->document->document_number}. New total {$currency} " . number_format($this->newTotal, 2) . ". {$payLine}. — {$this->tenant->name}",
        ];
    }

    public function toSms($notifiable): ?string
    {
        $currency = $this->tenant->currency;
        $feeFormatted = number_format($this->lateFeeAmount, 2);
        $newTotalFormatted = number_format($this->newTotal, 2);

        $msg = "OVERDUE: Invoice {$this->document->document_number} has a 10% late fee of {$currency} {$feeFormatted} applied. New total: {$currency} {$newTotalFormatted}. Please pay promptly. — {$this->tenant->name}";

        if ($this->tenant->pesapal_enabled && $this->document->balance_due > 0) {
            $payUrl = $this->tenantPortalUrl($this->document->tenant, "/pay/{$this->document->id}");
            $msg .= " Pay: {$payUrl}";
        }

        return $msg;
    }
}
