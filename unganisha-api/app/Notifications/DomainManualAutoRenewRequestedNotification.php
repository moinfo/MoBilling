<?php

namespace App\Notifications;

use App\Models\Domain;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * A client turned auto-renew ON for an unmanaged domain (no registrar
 * driver) via `PortalDomainController::setAutoRenew()`. The portal shows
 * it as enabled, but the real `auto_renew` column stays false so the
 * nightly renewal cron never touches it — staff need to renew this domain
 * by hand each cycle, before it expires.
 */
class DomainManualAutoRenewRequestedNotification extends Notification implements ShouldQueue
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
            'title' => 'Manual auto-renew requested',
            'body'  => "{$this->domain->name} — client expects it renewed automatically each cycle",
            'data'  => ['type' => 'domain_manual_auto_renew', 'domain_id' => $this->domain->id],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        return (new MailMessage)
            ->subject("Manual auto-renew requested — {$this->domain->name}")
            ->line("{$this->domain->name} is not connected to a registrar integration, so it cannot be auto-renewed by the system.")
            ->line('The client has enabled auto-renew and expects this domain to be renewed automatically before it expires — please renew it by hand each cycle.')
            ->action('View domain', url("/domains/{$this->domain->id}"));
    }

    public function toArray($notifiable): array
    {
        return [
            'type'      => 'domain_manual_auto_renew',
            'title'     => 'Manual auto-renew requested',
            'message'   => "{$this->domain->name} — client expects it renewed automatically each cycle",
            'domain_id' => $this->domain->id,
            'url'       => '/domains',
        ];
    }
}
