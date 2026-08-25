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

/**
 * Security alert: the domain's EPP transfer code was revealed. The code moves
 * the domain to another registrar, so the registrant must know it happened.
 */
class DomainAuthInfoRevealedNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    public function __construct(
        public Domain $domain,
        public Tenant $tenant,
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

        // Mobile push: FcmChannel no-ops when FCM_CREDENTIALS is unset and
        // when the client has no registered devices, so it is always safe on.
        $channels[] = \App\Channels\FcmChannel::class;

        return $channels;
    }

    public function toFcm($notifiable): ?array
    {
        // The EPP/transfer code itself must never be pushed — keep this generic.
        return [
            'title' => 'Domain transfer code accessed',
            'body'  => "The transfer (EPP) code for {$this->domain->name} was just accessed. If you didn't request it, contact us immediately.",
            'data'  => ['type' => 'domain', 'domain_id' => $this->domain->id],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        $mail = (new MailMessage)
            ->subject("Transfer Code Accessed — {$this->domain->name}")
            ->greeting("Hello {$notifiable->name},")
            ->line("The transfer (EPP) code for your domain **{$this->domain->name}** was just accessed.")
            ->line('This code can be used to transfer the domain to another registrar.')
            ->line('If you requested it, no action is needed. **If you did NOT, contact us immediately** so we can secure the domain.');

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toSms($notifiable): ?string
    {
        return "SECURITY: Transfer code (EPP) ya domain {$this->domain->name} imetolewa. "
            . "Kama hukuiomba, wasiliana nasi MARA MOJA. — {$this->tenant->name}";
    }

    public function toWhatsApp($notifiable): array
    {
        $alert = "The transfer (EPP) code for your domain {$this->domain->name} was just accessed";

        return [
            'template' => 'security_alert_v1',
            'parameters' => [$alert, $this->tenant->name],
            'language' => 'en',
            'fallback' => "🔐 SECURITY: {$alert}. This code can move the domain to another registrar. If you didn't request it, contact us immediately. — {$this->tenant->name}",
        ];
    }
}
