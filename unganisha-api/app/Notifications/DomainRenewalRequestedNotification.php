<?php

namespace App\Notifications;

use App\Models\Document;
use App\Models\Domain;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * A client requested a domain renewal from the portal
 * (`PortalDomainController::renew`) — creates the invoice; the registry
 * renewal itself only fires once it's paid. Fired to staff with
 * `domains.renew` so a renewal that never gets paid doesn't slip by
 * unnoticed until the domain is about to expire.
 */
class DomainRenewalRequestedNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(
        public Domain $domain,
        public int $years,
        public Document $document,
    ) {}

    public function via($notifiable): array
    {
        return ['database', \App\Channels\FcmChannel::class];
    }

    public function toFcm($notifiable): ?array
    {
        return [
            'title' => 'Domain renewal requested',
            'body'  => "{$this->domain->name} — {$this->years} year(s), invoice {$this->document->document_number}",
            'data'  => ['type' => 'domain_renewal', 'domain_id' => $this->domain->id],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        return (new MailMessage)
            ->subject("Domain renewal requested — {$this->domain->name}")
            ->line("{$this->domain->name} — renewal requested for {$this->years} year(s).")
            ->line("Invoice {$this->document->document_number} must be paid for the renewal to go through.")
            ->action('View invoice', url("/invoices?preview={$this->document->id}"));
    }

    public function toArray($notifiable): array
    {
        return [
            'type'    => 'domain_renewal',
            'title'   => 'Domain renewal requested',
            'message' => "{$this->domain->name} — {$this->years} year(s), invoice {$this->document->document_number}.",
            'domain_id' => $this->domain->id,
            'url'     => '/domains',
        ];
    }
}
