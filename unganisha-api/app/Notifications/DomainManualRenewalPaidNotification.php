<?php

namespace App\Notifications;

use App\Models\Document;
use App\Models\Domain;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * A renewal invoice for an unmanaged domain (no registrar driver) has been
 * paid — this is the moment it becomes actionable. Distinct from
 * DomainRenewalRequestedNotification, which fires earlier, at request
 * time, before the invoice is even paid.
 */
class DomainManualRenewalPaidNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(
        public Domain $domain,
        public Document $document,
    ) {}

    public function via($notifiable): array
    {
        return ['database', \App\Channels\FcmChannel::class];
    }

    public function toFcm($notifiable): ?array
    {
        return [
            'title' => 'Manual domain renewal paid — action needed',
            'body'  => "{$this->domain->name} — invoice {$this->document->document_number} paid, renew it now",
            'data'  => ['type' => 'domain_manual_renewal_paid', 'domain_id' => $this->domain->id],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        return (new MailMessage)
            ->subject("Manual domain renewal paid — {$this->domain->name}")
            ->line("{$this->domain->name} is not connected to a registrar integration, so the renewal must be applied by hand.")
            ->line("Invoice {$this->document->document_number} has been paid — please renew it at the actual registrar now.")
            ->action('View domain', url("/domains/{$this->domain->id}"));
    }

    public function toArray($notifiable): array
    {
        return [
            'type'      => 'domain_manual_renewal_paid',
            'title'     => 'Manual domain renewal paid — action needed',
            'message'   => "{$this->domain->name} — invoice {$this->document->document_number} paid, renew it now",
            'domain_id' => $this->domain->id,
            'url'       => '/domains',
        ];
    }
}
