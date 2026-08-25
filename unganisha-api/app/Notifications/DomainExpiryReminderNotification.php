<?php

namespace App\Notifications;

use App\Channels\SmsChannel;
use App\Channels\WhatsAppChannel;
use App\Models\Domain;
use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class DomainExpiryReminderNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    public function __construct(
        public Domain $domain,
        public Tenant $tenant,
        public int $daysLeft,
    ) {}

    public function via($notifiable): array
    {
        $channels = [];
        if ($this->tenant->email_enabled && $this->tenant->reminder_email_enabled && $notifiable->email) {
            $channels[] = 'mail';
        }
        if ($this->tenant->sms_enabled && $this->tenant->reminder_sms_enabled && $notifiable->phone) {
            $channels[] = SmsChannel::class;
        }
        if ($this->tenant->whatsapp_enabled && $this->tenant->reminder_whatsapp_enabled && $notifiable->phone) {
            $channels[] = WhatsAppChannel::class;
        }

        // Mobile push: FcmChannel no-ops when FCM_CREDENTIALS is unset and
        // when the client has no registered devices, so it is always safe on.
        $channels[] = \App\Channels\FcmChannel::class;

        return $channels;
    }

    public function toFcm($notifiable): ?array
    {
        $urgent = $this->daysLeft <= 7;

        return [
            'title' => ($urgent ? 'URGENT: ' : '') . "Domain {$this->domain->name} expires soon",
            'body'  => "Expires on {$this->domain->expires_at->format('d M Y')} — in {$this->daysLeft} day(s). Renew to avoid interruption.",
            'data'  => ['type' => 'domain', 'domain_id' => $this->domain->id],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        $expires = $this->domain->expires_at->format('d M Y');
        $urgent = $this->daysLeft <= 7;

        $mail = (new MailMessage)
            ->subject(($urgent ? 'URGENT: ' : '') . "Domain {$this->domain->name} expires in {$this->daysLeft} day(s)")
            ->greeting("Hello {$notifiable->name},")
            ->line("Your domain **{$this->domain->name}** expires on **{$expires}** — in **{$this->daysLeft} day(s)**.")
            ->line($urgent
                ? 'If it is not renewed, your website and email on this domain will STOP working, and the domain may become available for anyone to register.'
                : 'Please renew it in time to avoid any interruption to your website and email.')
            ->line('Contact us or log in to your client portal to renew.')
            ->line('Thank you.');

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toSms($notifiable): ?string
    {
        $expires = $this->domain->expires_at->format('d M Y');

        return "Domain {$this->domain->name} inaisha {$expires} (siku {$this->daysLeft}). "
            . "Ifanyie renew mapema kuepuka website/email kusimama. — {$this->tenant->name}";
    }

    public function toWhatsApp($notifiable): array
    {
        $expires = $this->domain->expires_at->format('d M Y');

        return [
            'template' => 'domain_expiry_v1',
            'parameters' => [$this->domain->name, $expires, (string) $this->daysLeft, $this->tenant->name],
            'language' => 'en',
            'fallback' => "⏰ Domain {$this->domain->name} expires {$expires} ({$this->daysLeft} days). Renew in time to keep your website and email running. — {$this->tenant->name}",
        ];
    }
}
