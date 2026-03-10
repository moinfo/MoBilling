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
        $channels = [];

        if ($this->tenant->email_enabled) {
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
        $totalFormatted = number_format($this->document->total, 2);

        $pdf = app(PdfService::class)->generate($this->document);
        $pdfContent = $pdf->output();

        $mail = (new MailMessage)
            ->subject("Payment Overdue — {$this->document->document_number} — {$this->tenant->name}")
            ->greeting("Hello {$this->document->client->name},")
            ->line("This is a reminder that invoice {$this->document->document_number} for {$currency} {$totalFormatted} is now {$this->daysOverdue} day(s) overdue.")
            ->line('Please make payment as soon as possible to avoid service disruption.');

        // Add "Pay Now" button if tenant has Pesapal enabled and invoice has balance
        if ($this->tenant->pesapal_enabled && $this->document->balance_due > 0) {
            $payUrl = config('app.frontend_url', 'https://mobilling.co.tz') . "/pay/{$this->document->id}";
            $mail->action('Pay Now', $payUrl);
        }

        $mail->line('Thank you.')
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

        $msg = "OVERDUE: Invoice {$this->document->document_number} for {$currency} {$totalFormatted} is {$this->daysOverdue} days overdue. Please pay immediately. — {$this->tenant->name}";

        if ($this->tenant->pesapal_enabled && $this->document->balance_due > 0) {
            $payUrl = config('app.frontend_url', 'https://mobilling.co.tz') . "/pay/{$this->document->id}";
            $msg .= " Pay: {$payUrl}";
        }

        return $msg;
    }

    public function toWhatsApp($notifiable): ?string
    {
        $currency = $this->tenant->currency;
        $totalFormatted = number_format($this->document->total, 2);
        $balanceDue = number_format($this->document->balance_due, 2);

        $msg = "🔴 *Payment Overdue*\n\n"
            . "*{$this->document->document_number}*\n"
            . "Amount: *{$currency} {$totalFormatted}*\n"
            . "Balance Due: *{$currency} {$balanceDue}*\n"
            . "Overdue by: *{$this->daysOverdue} day(s)*\n\n"
            . "⚠️ Please make payment immediately to avoid service disruption.";

        if ($this->tenant->pesapal_enabled && $this->document->balance_due > 0) {
            $payUrl = config('app.frontend_url', 'https://mobilling.co.tz') . "/pay/{$this->document->id}";
            $msg .= "\n\n💳 Pay online: {$payUrl}";
        }

        $msg .= "\n\n— {$this->tenant->name}";

        return $msg;
    }
}
