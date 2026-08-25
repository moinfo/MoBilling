<?php

namespace App\Notifications;

use App\Models\Domain;
use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/** SSL certificate on the client's domain is about to expire (email + push). */
class SslExpiryReminderNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    public function __construct(
        public Domain $domain,
        public Tenant $tenant,
        public int $daysLeft,
        public string $expiresAt,
    ) {}

    public function via($notifiable): array
    {
        $channels = ($this->tenant->email_enabled && $this->tenant->reminder_email_enabled && $notifiable->email)
            ? ['mail'] : [];

        // Mobile push: FcmChannel no-ops when FCM_CREDENTIALS is unset and
        // when the client has no registered devices, so it is always safe on.
        $channels[] = \App\Channels\FcmChannel::class;

        return $channels;
    }

    public function toFcm($notifiable): ?array
    {
        return [
            'title' => "SSL certificate for {$this->domain->name} expires in {$this->daysLeft} day(s)",
            'body'  => "Expires on {$this->expiresAt}. Renew it to avoid a browser security warning for visitors.",
            'data'  => ['type' => 'ssl', 'domain_id' => $this->domain->id],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        $mail = (new MailMessage)
            ->subject("SSL Certificate for {$this->domain->name} expires in {$this->daysLeft} day(s)")
            ->greeting("Hello {$notifiable->name},")
            ->line("The SSL certificate on **{$this->domain->name}** expires on **{$this->expiresAt}** ({$this->daysLeft} day(s) left).")
            ->line('When it expires, browsers will show a security warning to your visitors.')
            ->line('If your hosting is with us, the certificate usually renews automatically — this notice means it has not yet. Contact us if you are unsure.');

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }
}
