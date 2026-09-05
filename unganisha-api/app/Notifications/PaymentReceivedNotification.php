<?php

namespace App\Notifications;

use App\Models\Document;
use App\Models\PaymentIn;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * Money landed with no staff involved — an online gateway payment
 * (Pesapal), not one a staff member typed in themselves via
 * PaymentInController::store (which they already know about, having just
 * done it). Fired to staff with `payments_in.read`.
 */
class PaymentReceivedNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(
        public PaymentIn $payment,
        public Document $document,
    ) {}

    public function via($notifiable): array
    {
        return ['database', \App\Channels\FcmChannel::class];
    }

    public function toFcm($notifiable): ?array
    {
        return [
            'title' => 'Payment received',
            'body'  => number_format((float) $this->payment->amount, 2)
                . " for invoice {$this->document->document_number}",
            'data'  => ['type' => 'payment_received', 'document_id' => $this->document->id],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        return (new MailMessage)
            ->subject("Payment received — {$this->document->document_number}")
            ->line('A client just paid online.')
            ->line('Amount: ' . number_format((float) $this->payment->amount, 2))
            ->line("Invoice: {$this->document->document_number}")
            ->action('View invoice', url("/invoices?preview={$this->document->id}"));
    }

    public function toArray($notifiable): array
    {
        return [
            'type'    => 'payment_received',
            'title'   => 'Payment received',
            'message' => number_format((float) $this->payment->amount, 2)
                . " for invoice {$this->document->document_number}.",
            'document_id' => $this->document->id,
            'url'     => '/payments-in',
        ];
    }
}
