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
        // Push is independent of the mail channel; FcmChannel no-ops when
        // unconfigured or the recipient has no registered devices.
        return ['mail', \App\Channels\FcmChannel::class];
    }

    // SECURITY: never include the OTP itself here — a push is only used to
    // alert that a code was requested, in case someone else triggered it.
    public function toFcm($notifiable): ?array
    {
        return [
            'title' => 'Sign-in code requested',
            'body'  => "A sign-in code was requested for your {$this->tenantName} account.",
            'data'  => ['type' => 'otp_requested'],
        ];
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
