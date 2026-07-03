<?php

namespace App\Notifications;

use App\Models\Domain;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class DomainRegisteredNotification extends Notification
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
            ->subject("Domain registered: {$this->domain->name}")
            ->greeting("Hello {$notifiable->name},")
            ->line("Your domain **{$this->domain->name}** has been registered successfully.")
            ->line("**Expires:** " . ($this->domain->expires_at?->format('d M Y') ?? '—'))
            ->line('We will invoice you before it is due for renewal — nothing more to do for now.');

        return $this->applyBranding($mail, $this->domain->tenant);
    }
}
