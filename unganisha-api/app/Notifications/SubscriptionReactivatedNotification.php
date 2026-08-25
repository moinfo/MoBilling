<?php

namespace App\Notifications;

use App\Channels\SmsChannel;
use App\Channels\WhatsAppChannel;
use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * Payment landed and previously-suspended services came back — tell the
 * client, on every channel the tenant has switched on. One notification
 * covers all services restored by that payment.
 */
class SubscriptionReactivatedNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    /** @param string[] $labels restored service labels */
    public function __construct(
        public array $labels,
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
        $list = implode(', ', array_slice($this->labels, 0, 3))
            . (count($this->labels) > 3 ? ' +' . (count($this->labels) - 3) . ' more' : '');

        return [
            'title' => 'Service restored — thank you for your payment',
            'body'  => "Restored: {$list}.",
            'data'  => ['type' => 'subscription'],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        $mail = (new MailMessage)
            ->subject('Service Restored — Thank You for Your Payment')
            ->greeting("Hello {$notifiable->name},")
            ->line('Thank you for your payment. The following service(s) have been restored:');

        foreach ($this->labels as $label) {
            $mail->line("• {$label}");
        }

        $mail->line('Everything is back up and running. Thank you for staying with us!');
        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toSms($notifiable): ?string
    {
        $list = implode(', ', array_slice($this->labels, 0, 3))
            . (count($this->labels) > 3 ? ' +' . (count($this->labels) - 3) . ' more' : '');

        return "Payment received — service restored: {$list}. Asante! — {$this->tenant->name}";
    }

    public function toWhatsApp($notifiable): array
    {
        $list = implode(' · ', $this->labels);

        return [
            'template' => 'service_restored_v1',
            'parameters' => [$list, $this->tenant->name],
            'language' => 'en',
            'fallback' => "✅ Service restored: {$list}. Thank you for your payment! — {$this->tenant->name}",
        ];
    }
}
