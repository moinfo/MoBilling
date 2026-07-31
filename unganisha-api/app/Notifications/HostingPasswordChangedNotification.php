<?php

namespace App\Notifications;

use App\Channels\SmsChannel;
use App\Channels\WhatsAppChannel;
use App\Models\HostingAccount;
use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/** Security notice: the cPanel password was changed (never includes it). */
class HostingPasswordChangedNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    public function __construct(
        public HostingAccount $account,
        public Tenant $tenant,
        public string $changedVia,   // 'staff' | 'client portal'
    ) {}

    public function via($notifiable): array
    {
        $channels = [];
        if ($this->tenant->email_enabled && $notifiable->email) {
            $channels[] = 'mail';
        }
        if ($this->tenant->sms_enabled && $notifiable->phone) {
            $channels[] = SmsChannel::class;
        }
        if ($this->tenant->whatsapp_enabled && $notifiable->phone) {
            $channels[] = WhatsAppChannel::class;
        }

        return $channels;
    }

    public function toMail($notifiable): MailMessage
    {
        $mail = (new MailMessage)
            ->subject("cPanel Password Changed — {$this->account->domain}")
            ->greeting("Hello {$notifiable->name},")
            ->line("The cPanel password for **{$this->account->domain}** (user `{$this->account->cpanel_username}`) was just changed via the {$this->changedVia}.")
            ->line('If you made this change, no action is needed.')
            ->line('**If you did NOT make this change, contact us immediately** — your account may be at risk.');

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toSms($notifiable): ?string
    {
        return "SECURITY: cPanel password ya {$this->account->domain} imebadilishwa. "
            . "Kama si wewe, wasiliana nasi MARA MOJA. — {$this->tenant->name}";
    }

    public function toWhatsApp($notifiable): array
    {
        $alert = "The cPanel password for {$this->account->domain} was just changed via the {$this->changedVia}";

        return [
            'template' => 'security_alert_v1',
            'parameters' => [$alert, $this->tenant->name],
            'language' => 'en',
            'fallback' => "🔐 SECURITY: {$alert}. If this wasn't you, contact us immediately. — {$this->tenant->name}",
        ];
    }
}
