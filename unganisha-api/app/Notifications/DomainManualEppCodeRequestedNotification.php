<?php

namespace App\Notifications;

use App\Models\Domain;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * A client requested the transfer (EPP/auth-info) code for an unmanaged
 * domain (no registrar driver) via `PortalDomainController::eppCode()`.
 * The portal already told the client it was sent — staff must retrieve it
 * from wherever the domain is actually registered and email it directly.
 */
class DomainManualEppCodeRequestedNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(
        public Domain $domain,
    ) {}

    public function via($notifiable): array
    {
        return ['database', \App\Channels\FcmChannel::class];
    }

    public function toFcm($notifiable): ?array
    {
        return [
            'title' => 'Manual transfer code requested',
            'body'  => "{$this->domain->name} — send the EPP code to the client directly",
            'data'  => ['type' => 'domain_manual_epp', 'domain_id' => $this->domain->id],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        return (new MailMessage)
            ->subject("Manual transfer code requested — {$this->domain->name}")
            ->line("{$this->domain->name} is not connected to a registrar integration, so the transfer code can't be fetched automatically.")
            ->line('The client was told it has been sent — please retrieve it and email it to them directly.')
            ->action('View domain', url("/domains/{$this->domain->id}"));
    }

    public function toArray($notifiable): array
    {
        return [
            'type'      => 'domain_manual_epp',
            'title'     => 'Manual transfer code requested',
            'message'   => "{$this->domain->name} — send the EPP code to the client directly",
            'domain_id' => $this->domain->id,
            'url'       => '/domains',
        ];
    }
}
