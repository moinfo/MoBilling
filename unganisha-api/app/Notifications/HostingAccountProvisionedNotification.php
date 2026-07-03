<?php

namespace App\Notifications;

use App\Models\HostingAccount;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * Sent once, right after createacct. Carries the initial cPanel password —
 * which is intentionally NOT stored anywhere; sync send only (never queued,
 * the password must not be serialized to a queue store).
 */
class HostingAccountProvisionedNotification extends Notification
{
    use Queueable, HasTenantBranding;

    public function __construct(
        public HostingAccount $account,
        private string $password,
    ) {}

    public function via($notifiable): array
    {
        return ['mail'];
    }

    public function toMail($notifiable): MailMessage
    {
        $tenant = $this->account->tenant;
        $domain = $this->account->domain;

        $mail = (new MailMessage)
            ->subject("Your hosting account for {$domain} is ready")
            ->greeting("Hello {$notifiable->name},")
            ->line("Your hosting account has been created and is now active.")
            ->line("**Domain:** {$domain}")
            ->line("**cPanel username:** {$this->account->cpanel_username}")
            ->line("**cPanel password:** {$this->password}")
            ->line("**cPanel login:** https://{$this->account->server->hostname}:2083")
            ->line('Please change this password after your first login. Keep these credentials safe — this is the only time they will be sent.');

        return $this->applyBranding($mail, $tenant);
    }
}
