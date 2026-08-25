<?php

namespace App\Notifications;

use App\Models\Domain;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class DomainRenewedNotification extends Notification
{
    use Queueable, HasTenantBranding;

    public function __construct(public Domain $domain) {}

    public function via($notifiable): array
    {
        // Mobile push: FcmChannel no-ops when FCM_CREDENTIALS is unset and
        // when the client has no registered devices, so it is always safe on.
        return ['mail', \App\Channels\FcmChannel::class];
    }

    public function toFcm($notifiable): ?array
    {
        return [
            'title' => "Domain renewed: {$this->domain->name}",
            'body'  => "Your domain {$this->domain->name} has been renewed. New expiry "
                . ($this->domain->expires_at?->format('d M Y') ?? '—') . '.',
            'data'  => ['type' => 'domain', 'domain_id' => $this->domain->id],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        $mail = (new MailMessage)
            ->subject("Domain renewed: {$this->domain->name}")
            ->greeting("Hello {$notifiable->name},")
            ->line("Your domain **{$this->domain->name}** has been renewed.")
            ->line("**New expiry:** " . ($this->domain->expires_at?->format('d M Y') ?? '—'))
            ->action('Manage Your Domain', $this->tenantPortalUrl($this->domain->tenant, "/portal/domains/{$this->domain->id}"))
            ->line('Thank you for your payment.');

        return $this->applyBranding($mail, $this->domain->tenant);
    }
}
