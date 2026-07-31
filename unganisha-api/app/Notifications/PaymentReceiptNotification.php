<?php

namespace App\Notifications;

use App\Channels\SmsChannel;
use App\Channels\WhatsAppChannel;
use App\Models\Document;
use App\Models\PaymentIn;
use App\Notifications\Concerns\HasTenantBranding;
use App\Services\PdfService;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class PaymentReceiptNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    public function __construct(
        public PaymentIn $payment,
        public Document $document,
    ) {}

    public function via($notifiable): array
    {
        $this->document->loadMissing(['tenant' => fn ($q) => $q->withoutGlobalScopes()]);
        $tenant = $this->document->tenant;

        $channels = [];
        if ($tenant?->email_enabled && $notifiable->email) {
            $channels[] = 'mail';
        }
        if ($tenant?->sms_enabled && $notifiable->phone) {
            $channels[] = SmsChannel::class;
        }
        if ($tenant?->whatsapp_enabled && $notifiable->phone) {
            $channels[] = WhatsAppChannel::class;
        }

        return $channels;
    }

    public function toSms($notifiable): ?string
    {
        $tenant = $this->document->tenant;
        $amount = $tenant->currency . ' ' . number_format($this->payment->amount, 2);
        $paid = $this->document->status === 'paid';

        return "Payment received: {$amount} for invoice {$this->document->document_number}."
            . ($paid ? ' Invoice fully PAID.' : ' Balance: ' . $tenant->currency . ' ' . number_format($this->document->balance_due, 2) . '.')
            . " Asante! — {$tenant->name}";
    }

    public function toWhatsApp($notifiable): array
    {
        $tenant = $this->document->tenant;
        $amount = $tenant->currency . ' ' . number_format($this->payment->amount, 2);
        $paid = $this->document->status === 'paid';
        $statusLine = $paid
            ? 'Your invoice is now fully PAID.'
            : 'Remaining balance: ' . $tenant->currency . ' ' . number_format($this->document->balance_due, 2);

        return [
            'template' => 'payment_received_v1',
            'parameters' => [$this->document->document_number, $amount, $statusLine, $tenant->name],
            'language' => 'en',
            'fallback' => "✅ Payment received: {$amount} for invoice {$this->document->document_number}. {$statusLine} — {$tenant->name}",
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        $this->document->loadMissing(['items', 'client', 'tenant' => fn ($q) => $q->withoutGlobalScopes()]);

        $tenant = $this->document->tenant;
        $client = $this->document->client;
        $amount = $tenant->currency . ' ' . number_format($this->payment->amount, 2);
        $isPaid = $this->document->status === 'paid';

        $pdf = app(PdfService::class)->generateReceipt($this->payment, $this->document);
        $pdfContent = $pdf->output();

        $receiptNumber = 'RCT-' . $this->payment->payment_date->format('Ymd') . '-' . strtoupper(substr($this->payment->id, 0, 6));

        $mail = (new MailMessage)
            ->subject(($isPaid ? 'Payment Confirmed (PAID)' : 'Payment Receipt') . " — {$this->document->document_number} — {$tenant->name}")
            ->greeting("Hello {$client->name},")
            ->line("Thank you for your payment of **{$amount}** towards invoice **{$this->document->document_number}**.")
            ->line("Payment date: {$this->payment->payment_date->format('d M Y')}");

        if ($isPaid) {
            $mail->line('**Your invoice has been fully paid.** Please find your receipt and paid invoice attached.');
        } else {
            $totalFormatted = $tenant->currency . ' ' . number_format($this->document->balance_due, 2);
            $mail->line("Remaining balance: **{$totalFormatted}**")
                 ->line('Please find your payment receipt attached.');
        }

        $mail->line('Thank you for your business.');

        $this->applyBranding($mail, $tenant);

        $mail->attachData($pdfContent, "{$receiptNumber}.pdf", [
            'mime' => 'application/pdf',
        ]);

        // Attach the invoice PDF with current status (PAID stamp if fully paid)
        if ($isPaid) {
            $invoicePdf = app(PdfService::class)->generate($this->document);
            $mail->attachData($invoicePdf->output(), "{$this->document->document_number}.pdf", [
                'mime' => 'application/pdf',
            ]);
        }

        return $mail;
    }
}
