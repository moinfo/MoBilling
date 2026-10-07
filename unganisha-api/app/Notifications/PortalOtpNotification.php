<?php

namespace App\Notifications;

use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class PortalOtpNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    public function __construct(
        public string $otp,
        public string $tenantName,
        public ?Tenant $tenant = null,
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
        $mail = (new MailMessage)
            ->subject("Your Portal Access Code — {$this->tenantName}")
            ->greeting("Hello,")
            ->line("You requested access to the {$this->tenantName} client portal.")
            ->line("Your verification code is:")
            ->line("**{$this->otp}**")
            ->line('This code expires in 10 minutes.')
            ->line('If you did not request this, please ignore this email.')
            ->salutation("Regards, {$this->tenantName}");

        // Without this, every white-label tenant's OTP email went out from the
        // platform's own mailer/From address — the content said the tenant's
        // name, but the sender a client actually sees was always MoBilling.
        if ($this->tenant) {
            $this->applyBranding($mail, $this->tenant);
        }

        return $mail;
    }
}
