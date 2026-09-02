<?php

namespace App\Notifications;

use App\Channels\SmsChannel;
use App\Channels\WhatsAppChannel;
use App\Models\Broadcast;
use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class BroadcastNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    public function __construct(
        public Broadcast $broadcast,
        public Tenant $tenant,
    ) {}

    public function via($notifiable): array
    {
        $channels = match ($this->broadcast->channel) {
            'email'    => ['mail'],
            'sms'      => [SmsChannel::class],
            'whatsapp' => [WhatsAppChannel::class],
            'both'     => ['mail', SmsChannel::class],
        };

        // Push is independent of the broadcast's chosen channel; FcmChannel
        // no-ops when unconfigured or the client has no registered devices.
        $channels[] = \App\Channels\FcmChannel::class;

        return $channels;
    }

    public function toFcm($notifiable): ?array
    {
        return [
            'title' => $this->broadcast->subject,
            'body'  => \Illuminate\Support\Str::limit(trim(strip_tags($this->broadcast->body)), 150),
            'data'  => ['type' => 'broadcast', 'broadcast_id' => $this->broadcast->id],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        $mail = (new MailMessage)->subject($this->broadcast->subject);

        foreach (explode("\n", $this->broadcast->body) as $line) {
            $mail->line($line ?: ' ');
        }

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toSms($notifiable): string
    {
        return $this->broadcast->sms_body;
    }

    public function toWhatsApp($notifiable): string
    {
        return $this->broadcast->whatsapp_body;
    }
}
