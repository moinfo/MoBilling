<?php

namespace App\Notifications;

use App\Models\Domain;
use App\Notifications\Concerns\HasTenantBranding;
use App\Notifications\Concerns\SendsDomainWhatsApp;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/** CUSTOMER-facing, deliberately neutral: no supplier, cost or registrar wording. */
class DomainReadyNotification extends Notification
{
    use Queueable, HasTenantBranding, SendsDomainWhatsApp;

    public function __construct(public Domain $domain) {}

    public function via($notifiable): array
    {
        return $this->withWhatsApp(['mail', \App\Channels\FcmChannel::class], $notifiable);
    }

    public function toFcm($notifiable): ?array
    {
        return ['title' => "Your domain {$this->domain->name} is ready",
            'body' => "Your domain {$this->domain->name} is ready. You can manage it from your portal.",
            'data' => ['type' => 'domain', 'domain_id' => $this->domain->id]];
    }

    public function toWhatsApp($notifiable): string
    {
        return $this->waText(
            "Habari {$notifiable->name}, domain yako {$this->domain->name} iko tayari. Inaisha: {$this->waExpiry()}.",
            "Hello {$notifiable->name}, your domain {$this->domain->name} is ready. Expires: {$this->waExpiry()}."
        );
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
