<?php

namespace App\Notifications;

use App\Channels\SmsChannel;
use App\Channels\WhatsAppChannel;
use App\Models\Domain;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * BaseDomainJob::guard() used to only Log::error() a failed register/
 * transfer/renew — the client never found out, so a bad transfer auth
 * code (the common case) sat failed until staff happened to notice.
 */
class DomainActionFailedNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(
        public Domain $domain,
        public string $action,
        public string $reason,
    ) {}

    public function via($notifiable): array
    {
        $tenant = \App\Models\Tenant::withoutGlobalScopes()->find($this->domain->tenant_id);
        $channels = ['database'];

        if ($tenant?->email_enabled && $notifiable->email) {
            $channels[] = 'mail';
        }
        if ($tenant?->sms_enabled && $tenant->reminder_sms_enabled) {
            $channels[] = SmsChannel::class;
        }
        if ($tenant?->whatsapp_enabled && $tenant->reminder_whatsapp_enabled) {
            $channels[] = WhatsAppChannel::class;
        }
        $channels[] = \App\Channels\FcmChannel::class;

        return $channels;
    }

    protected function message(): string
    {
        $actionName = match ($this->action) {
            'transfer' => 'transfer',
            'renew' => 'renewal',
            default => 'registration',
        };
        $help = $this->action === 'transfer'
            ? ' Please send us the correct transfer authorization (EPP) code so we can try again.'
            : ' Please contact us so we can resolve this and try again.';

        return "{$this->domain->name} {$actionName} failed: {$this->reason}.{$help}";
    }

    public function toFcm($notifiable): ?array
    {
        return [
            'title' => "Domain {$this->action} failed",
            'body'  => $this->message(),
            'data'  => ['type' => 'domain_action_failed', 'domain_id' => $this->domain->id],
        ];
    }

    public function toWhatsApp($notifiable): string
    {
        return "⚠️ " . $this->message();
    }

    public function toSms($notifiable): ?string
    {
        return $this->message();
    }

    public function toMail($notifiable): MailMessage
    {
        return (new MailMessage)
            ->subject("Domain {$this->action} failed — {$this->domain->name}")
            ->line($this->message());
    }

    public function toArray($notifiable): array
    {
        return [
            'type'      => 'domain_action_failed',
            'title'     => "Domain {$this->action} failed",
            'message'   => $this->message(),
            'domain_id' => $this->domain->id,
            'url'       => '/domains',
        ];
    }
}
