<?php

namespace App\Notifications;

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
        return ['mail'];
    }

    public function toMail($notifiable): MailMessage
    {
        $this->document->loadMissing(['client', 'tenant' => fn ($q) => $q->withoutGlobalScopes()]);

        $tenant = $this->document->tenant;
        $client = $this->document->client;
        $amount = $tenant->currency . ' ' . number_format($this->payment->amount, 2);

        $pdf = app(PdfService::class)->generateReceipt($this->payment, $this->document);
        $pdfContent = $pdf->output();

        $receiptNumber = 'RCT-' . $this->payment->payment_date->format('Ymd') . '-' . strtoupper(substr($this->payment->id, 0, 6));

        $mail = (new MailMessage)
            ->subject("Payment Receipt — {$this->document->document_number} — {$tenant->name}")
            ->greeting("Hello {$client->name},")
            ->line("Thank you for your payment of **{$amount}** towards invoice **{$this->document->document_number}**.")
            ->line("Payment date: {$this->payment->payment_date->format('d M Y')}")
            ->line('Please find your payment receipt attached.')
            ->line('Thank you for your business.');

        $this->applyBranding($mail, $tenant);

        return $mail->attachData($pdfContent, "{$receiptNumber}.pdf", [
            'mime' => 'application/pdf',
        ]);
    }
}
