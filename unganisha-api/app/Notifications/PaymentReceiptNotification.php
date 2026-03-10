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
        $this->document->loadMissing(['tenant' => fn ($q) => $q->withoutGlobalScopes()]);
        $tenant = $this->document->tenant;

        if ($tenant && !$tenant->email_enabled) {
            return [];
        }

        return ['mail'];
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
