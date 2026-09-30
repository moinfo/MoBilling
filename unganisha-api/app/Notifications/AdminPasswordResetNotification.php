<?php

namespace App\Notifications;

use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * Staff-initiated reset from /admin/tenants — unlike ResetPasswordNotification
 * (a self-service reset LINK, currently unused by any live route — the app's
 * actual forgot-password flow is PasswordResetController's OTP system) this
 * carries the new plaintext password directly, since a superadmin generated
 * it on the user's behalf and there's no self-service token step to link to.
 */
class AdminPasswordResetNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    public function __construct(
        public Tenant $tenant,
        public string $newPassword,
    ) {}

    public function via($notifiable): array
    {
        return ['mail'];
    }

    public function toMail($notifiable): MailMessage
    {
        $mail = (new MailMessage)
            ->subject("Your password was reset — {$this->tenant->name}")
            ->greeting("Hi {$notifiable->name},")
            ->line('An administrator reset your MoBilling password. Your new temporary password is:')
            ->line("**{$this->newPassword}**")
            ->line('Please sign in with it and change it right away from your profile settings.')
            ->action('Sign in', config('app.frontend_url', 'http://localhost:5173') . '/login')
            ->line('If you did not expect this, contact your administrator immediately.');

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toArray($notifiable): array
    {
        return [
            'type' => 'admin_password_reset',
            'title' => 'Password reset',
            'message' => 'An administrator reset your password. Check your email for the new one.',
        ];
    }
}
