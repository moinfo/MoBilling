<?php

namespace App\Notifications;

use App\Channels\SmsChannel;
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
        return match ($this->broadcast->channel) {
            'email' => ['mail'],
            'sms'   => [SmsChannel::class],
            'both'  => ['mail', SmsChannel::class],
        };
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
}
