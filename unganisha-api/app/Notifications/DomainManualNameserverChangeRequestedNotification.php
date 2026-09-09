<?php

namespace App\Notifications;

use App\Models\Domain;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * A client requested a nameserver change on an unmanaged domain (no
 * registrar driver) via `PortalDomainController::updateNameservers()`.
 * The portal already told the client it succeeded — staff must apply the
 * change by hand at wherever the domain is actually registered.
 */
class DomainManualNameserverChangeRequestedNotification extends Notification implements ShouldQueue
{
    use Queueable;

    /** @param string[] $nameservers */
    public function __construct(
        public Domain $domain,
        public array $nameservers,
    ) {}

    public function via($notifiable): array
    {
        return ['database', \App\Channels\FcmChannel::class];
    }

    public function toFcm($notifiable): ?array
    {
        return [
            'title' => 'Manual nameserver change requested',
            'body'  => "{$this->domain->name} — " . implode(', ', $this->nameservers),
            'data'  => ['type' => 'domain_manual_nameservers', 'domain_id' => $this->domain->id],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        return (new MailMessage)
            ->subject("Manual nameserver change requested — {$this->domain->name}")
            ->line("{$this->domain->name} is not connected to a registrar integration, so this needs to be applied by hand.")
            ->line('Requested nameservers: ' . implode(', ', $this->nameservers))
            ->action('View domain', url("/domains/{$this->domain->id}"));
    }

    public function toArray($notifiable): array
    {
        return [
            'type'      => 'domain_manual_nameservers',
            'title'     => 'Manual nameserver change requested',
            'message'   => "{$this->domain->name} — " . implode(', ', $this->nameservers),
            'domain_id' => $this->domain->id,
            'url'       => '/domains',
        ];
    }
}
