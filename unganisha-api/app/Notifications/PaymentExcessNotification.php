<?php

namespace App\Notifications;

use App\Models\Document;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Notification;

/**
 * An online payment arrived for an invoice that was already paid/cancelled
 * (or overpaid it). The excess was credited to the client wallet when
 * possible; staff are told so they can review or refund.
 */
class PaymentExcessNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(
        public Document $document,
        public float $excess,
        public bool $credited,
    ) {}

    public function via($notifiable): array
    {
        return ['database', \App\Channels\FcmChannel::class];
    }

    private function text(): string
    {
        return number_format($this->excess, 2) . " received online for invoice {$this->document->document_number}"
            . ' after it was already paid/cancelled. '
            . ($this->credited ? 'Added to the client credit balance.' : 'Not credited automatically; please review.');
    }

    public function toFcm($notifiable): ?array
    {
        return [
            'title' => 'Duplicate payment',
            'body'  => $this->text(),
            'data'  => ['type' => 'payment_excess', 'document_id' => $this->document->id],
        ];
    }

    public function toArray($notifiable): array
    {
        return [
            'type'        => 'payment_excess',
            'title'       => 'Duplicate payment',
            'message'     => $this->text(),
            'document_id' => $this->document->id,
            'url'         => '/payments-in',
        ];
    }
}
