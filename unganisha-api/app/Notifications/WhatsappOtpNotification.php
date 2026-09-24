<?php

namespace App\Notifications;

use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/** Email carrying a one-time verification code (sent synchronously so a delivery failure is known). */
class WhatsappOtpNotification extends Notification
{
    use HasTenantBranding;

    public function __construct(public Tenant $tenant, public string $code, public string $domain, public int $minutes = 10) {}

    public function via($notifiable): array
    {
        return ['mail'];
    }

    public function toMail($notifiable): MailMessage
    {
        $mail = (new MailMessage)
            ->subject("Verification code / Nambari ya uthibitisho — {$this->domain}")
            ->greeting("Hello / Habari {$notifiable->name},")
            ->line("Your code to reset the cPanel password of **{$this->domain}** via WhatsApp is:")
            ->line("## {$this->code}")
            ->line("It is valid for {$this->minutes} minutes and can be used once. / Nambari hii ni ya dakika {$this->minutes} na hutumika mara moja tu.")
            ->line('If you did not ask for this, ignore this email and do not share the code with anyone. / Kama si wewe, puuza barua hii na usimpe mtu nambari hii.');

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }
}
