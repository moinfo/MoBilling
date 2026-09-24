<?php

namespace App\Notifications;

use App\Models\Domain;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/** CUSTOMER-facing, deliberately neutral: no supplier, cost or registrar wording. */
class DomainReadyNotification extends Notification
{
    use Queueable, HasTenantBranding;

    public function __construct(public Domain $domain) {}

    public function via($notifiable): array
    {
        return ['mail', \App\Channels\FcmChannel::class];
    }

    public function toFcm($notifiable): ?array
    {
        return ['title' => "Your domain {$this->domain->name} is ready",
            'body' => "Your domain {$this->domain->name} is ready. You can manage it from your portal.",
            'data' => ['type' => 'domain', 'domain_id' => $this->domain->id]];
    }

    public function toMail($notifiable): MailMessage
    {
        $mail = (new MailMessage)
            ->subject("Your domain {$this->domain->name} is ready")
            ->greeting("Hello {$notifiable->name},")
            ->line("Your domain **{$this->domain->name}** is ready.")
            ->line('**Expires:** ' . ($this->domain->expires_at?->format('d M Y') ?? '—'))
            ->action('Manage Your Domain', $this->tenantPortalUrl($this->domain->tenant, "/portal/domains/{$this->domain->id}"));

        return $this->applyBranding($mail, $this->domain->tenant);
    }
}
