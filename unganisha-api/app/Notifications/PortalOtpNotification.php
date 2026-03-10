<?php

namespace App\Notifications;

use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class PortalOtpNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(
        public string $otp,
        public string $tenantName,
    ) {}

    public function via($notifiable): array
    {
        return ['mail'];
    }

    public function toMail($notifiable): MailMessage
    {
        return (new MailMessage)
            ->subject("Your Portal Access Code — {$this->tenantName}")
            ->greeting("Hello,")
            ->line("You requested access to the {$this->tenantName} client portal.")
            ->line("Your verification code is:")
            ->line("**{$this->otp}**")
            ->line('This code expires in 10 minutes.')
            ->line('If you did not request this, please ignore this email.')
            ->salutation('Regards, The MoBilling Team');
    }
}
