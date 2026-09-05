<?php

namespace App\Notifications;

use App\Models\Document;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * A client placed an order (hosting, domain, product, or add-on) through
 * the portal's self-service order flow. Fired to staff with `orders.create`
 * — nothing told them before this; the order just sat in the invoices list
 * until someone happened to check it.
 */
class OrderPlacedNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(
        public Document $document,
        public string $summary,
    ) {}

    public function via($notifiable): array
    {
        return ['database', 'mail', \App\Channels\FcmChannel::class];
    }

    public function toFcm($notifiable): ?array
    {
        return [
            'title' => 'New order placed',
            'body'  => "{$this->summary} — invoice {$this->document->document_number}",
            'data'  => ['type' => 'order', 'document_id' => $this->document->id],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        return (new MailMessage)
            ->subject("New order — {$this->document->document_number}")
            ->line("A client placed a new order: {$this->summary}.")
            ->line("Invoice {$this->document->document_number} for " . number_format((float) $this->document->total, 2) . ' has been generated.')
            ->action('View invoice', url("/invoices?preview={$this->document->id}"));
    }

    public function toArray($notifiable): array
    {
        return [
            'type'    => 'order',
            'title'   => 'New order placed',
            'message' => "{$this->summary} — invoice {$this->document->document_number}.",
            'document_id' => $this->document->id,
            'url'     => '/invoices',
        ];
    }
}
