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

class InvoiceTerminationWarningNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    public function __construct(
        public Document $document,
        public Tenant $tenant,
    ) {}

    public function via($notifiable): array
    {
        $channels = [];

        if ($this->tenant->email_enabled && $notifiable->email) {
            $channels[] = 'mail';
        }

        if ($this->tenant->sms_enabled) {
            $channels[] = SmsChannel::class;
        }

        if ($this->tenant->whatsapp_enabled) {
            $channels[] = WhatsAppChannel::class;
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
            ->line('Please settle this invoice immediately to avoid service disruption.');

        if ($this->tenant->pesapal_enabled && $this->document->balance_due > 0) {
            $payUrl = $this->tenantPortalUrl($this->document->tenant, "/pay/{$this->document->id}");
            $mail->action('Pay Now', $payUrl);
        }

        $mail->line("If you have already made payment, please disregard this notice and contact us with your payment reference.")
            ->line('Thank you.')
            ->attachData($pdfContent, "{$this->document->document_number}.pdf", [
                'mime' => 'application/pdf',
            ]);

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toWhatsApp($notifiable): array
    {
        $currency = $this->tenant->currency;
        $amount = "{$currency} " . number_format($this->document->total, 2);
        $payable = $this->tenant->pesapal_enabled && $this->document->balance_due > 0;

        if ($payable) {
            return [
                'template' => 'final_notice_v2',
                'parameters' => [$this->document->document_number, $amount, $this->tenant->name],
                'language' => 'en',
                'button_url' => (string) $this->document->id,
                'fallback' => "🚨 FINAL NOTICE: Invoice {$this->document->document_number} ({$amount}) unpaid — service terminates in 7 days. Pay now: " . $this->tenantPortalUrl($this->document->tenant, "/pay/{$this->document->id}") . " — {$this->tenant->name}",
            ];
        }

        return [
            'template' => 'final_notice_v1',
            'parameters' => [$this->document->document_number, $amount, 'Contact us to pay', $this->tenant->name],
            'language' => 'en',
            'fallback' => "🚨 FINAL NOTICE: Invoice {$this->document->document_number} ({$amount}) unpaid — service terminates in 7 days. — {$this->tenant->name}",
        ];
    }

    public function toSms($notifiable): ?string
    {
        $currency = $this->tenant->currency;
        $totalFormatted = number_format($this->document->total, 2);

        $msg = "FINAL NOTICE: Invoice {$this->document->document_number} ({$currency} {$totalFormatted}) is unpaid. Service will be TERMINATED in 7 days if not cleared. Pay now. — {$this->tenant->name}";

        if ($this->tenant->pesapal_enabled && $this->document->balance_due > 0) {
            $payUrl = $this->tenantPortalUrl($this->document->tenant, "/pay/{$this->document->id}");
            $msg .= " Pay: {$payUrl}";
        }

        return $msg;
    }
}
