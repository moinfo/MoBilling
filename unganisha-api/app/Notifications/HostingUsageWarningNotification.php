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
 * A hosting account's disk or bandwidth usage crossed a warning threshold.
 * Uses the same "reminder" channel toggles as DomainExpiryReminderNotification
 * (a tenant can turn reminders off separately from transactional mail).
 */
class HostingUsageWarningNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    /** @param 'disk'|'bandwidth' $metric */
    public function __construct(
        public HostingAccount $account,
        public Tenant $tenant,
        public string $metric,
        public float $percent,
        public bool $atLimit,
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

        $channels[] = \App\Channels\FcmChannel::class;

        return $channels;
    }

    private function metricLabel(): string
    {
        return $this->metric === 'bandwidth' ? 'bandwidth' : 'disk space';
    }

    private function headline(): string
    {
        $label = $this->metricLabel();
        return $this->atLimit
            ? ucfirst("{$label} is full")
            : ucfirst("{$label} is nearing its limit");
    }

    public function toFcm($notifiable): ?array
    {
        return [
            'title' => "{$this->headline()} — {$this->account->domain}",
            'body'  => sprintf('%s is at %.0f%% of its limit.', ucfirst($this->metricLabel()), $this->percent),
            'data'  => ['type' => 'hosting_usage', 'hosting_account_id' => $this->account->id],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        $mail = (new MailMessage)
            ->subject("{$this->headline()} — {$this->account->domain}")
            ->greeting("Hello {$notifiable->name},")
            ->line(sprintf(
                'Your hosting account **%s** is using **%.0f%%** of its %s limit.',
                $this->account->domain,
                $this->percent,
                $this->metricLabel(),
            ))
            ->line($this->atLimit
                ? ($this->metric === 'bandwidth'
                    ? 'Once bandwidth is fully used, visitors may not be able to reach your website until the next billing cycle or an upgrade.'
                    : 'Once disk space is full, your website, email and backups on this account can start failing.')
                : 'Please consider freeing up space or upgrading your plan soon to avoid any interruption.')
            ->line('To see your hosting status on WhatsApp, type HUDUMA, then choose Website Hosting, then My hosting (Hosting yangu).')
            ->line('To upgrade your plan, please contact us or log in to your client portal.')
            ->line('Thank you.');

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toSms($notifiable): ?string
    {
        $label = $this->metric === 'bandwidth' ? 'Bandwidth' : 'Disk space';

        return sprintf(
            '%s ya %s ipo %.0f%% ya limit. %s — %s',
            $label,
            $this->account->domain,
            $this->percent,
            ($this->atLimit ? 'Tafadhali wasiliana nasi haraka kuepuka usumbufu.' : 'Fikiria ku-upgrade au kufuta files zisizohitajika.')
                . ' Kuona hali ya hosting andika HUDUMA > Website Hosting > Hosting yangu.',
            $this->tenant->name,
        );
    }

    public function toWhatsApp($notifiable): array
    {
        $label = $this->metric === 'bandwidth' ? 'Bandwidth' : 'Disk space';
        $pct = sprintf('%.0f', $this->percent);

        return [
            'template' => 'hosting_usage_warning_v1',
            'parameters' => [$this->account->domain, $label, $pct, $this->tenant->name],
            'language' => 'en',
            'fallback' => sprintf(
                '%s %s ya %s ipo %s%% ya limit. %s — %s',
                $this->atLimit ? '⚠️' : '📊',
                $label,
                $this->account->domain,
                $pct,
                ($this->atLimit ? 'Tafadhali wasiliana nasi haraka.' : 'Fikiria ku-upgrade (wasiliana nasi) au kusafisha files.')
                    . ' Kuona hali ya hosting andika HUDUMA > Website Hosting > Hosting yangu.',
                $this->tenant->name,
            ),
        ];
    }
}
