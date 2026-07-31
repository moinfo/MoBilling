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

/**
 * Admin-initiated hosting suspend/unsuspend. (The unpaid-invoice flow has its
 * own subscription notifications — this covers manual admin actions, which
 * were previously silent.)
 */
class HostingStatusChangedNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    public function __construct(
        public HostingAccount $account,
        public Tenant $tenant,
        public bool $suspended,          // true = suspended, false = restored
        public ?string $reason = null,
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
            ->subject(($this->suspended ? 'Hosting Suspended — ' : 'Hosting Restored — ') . $this->account->domain)
            ->greeting("Hello {$notifiable->name},");

        if ($this->suspended) {
            $mail->line("Your hosting account **{$this->account->domain}** has been suspended" . ($this->reason ? " ({$this->reason})" : '') . '.')
                ->line('Your website and email on this domain are temporarily unavailable. Please contact us to resolve this.');
        } else {
            $mail->line("Your hosting account **{$this->account->domain}** has been restored — your website and email are back online.");
        }

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toSms($notifiable): ?string
    {
        return $this->suspended
            ? "Hosting ya {$this->account->domain} imesimamishwa. Wasiliana nasi kuirejesha. — {$this->tenant->name}"
            : "Hosting ya {$this->account->domain} imerudishwa — website/email zinafanya kazi. — {$this->tenant->name}";
    }

    public function toWhatsApp($notifiable): array
    {
        $service = "hosting {$this->account->domain}";

        if ($this->suspended) {
            $reason = $this->reason ?: 'Contact us for details';

            return [
                'template' => 'service_suspended_v1',
                'parameters' => [$service, $reason, $this->tenant->name],
                'language' => 'en',
                'fallback' => "⛔ Hosting {$this->account->domain} suspended ({$reason}). Contact us to resolve. — {$this->tenant->name}",
            ];
        }

        return [
            'template' => 'service_restored_v1',
            'parameters' => [$service, $this->tenant->name],
            'language' => 'en',
            'fallback' => "✅ Hosting {$this->account->domain} restored — website and email back online. — {$this->tenant->name}",
        ];
    }
}
