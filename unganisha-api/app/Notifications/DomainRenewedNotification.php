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
        return ['mail'];
    }

    public function toMail($notifiable): MailMessage
    {
        $mail = (new MailMessage)
            ->subject("Domain renewed: {$this->domain->name}")
            ->greeting("Hello {$notifiable->name},")
            ->line("Your domain **{$this->domain->name}** has been renewed.")
            ->line("**New expiry:** " . ($this->domain->expires_at?->format('d M Y') ?? '—'))
            ->line('Thank you for your payment.');

        return $this->applyBranding($mail, $this->domain->tenant);
    }
}
