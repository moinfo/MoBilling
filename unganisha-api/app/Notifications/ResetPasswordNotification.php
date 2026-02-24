<?php

namespace App\Notifications;

use App\Models\PlatformSetting;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class ResetPasswordNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(public string $token) {}

    public function via($notifiable): array
    {
        return ['mail'];
    }

    public function toMail($notifiable): MailMessage
    {
        $frontendUrl = config('app.frontend_url', 'http://localhost:5173');
        $resetUrl = $frontendUrl . '/reset-password?token=' . $this->token . '&email=' . urlencode($notifiable->getEmailForPasswordReset());

        $replacements = [
            '{user_name}' => $notifiable->name,
            '{reset_url}' => $resetUrl,
        ];

        $subject = PlatformSetting::get('reset_password_email_subject');
        $body = PlatformSetting::get('reset_password_email_body');

        if ($subject && $body) {
            $subject = str_replace(array_keys($replacements), array_values($replacements), $subject);
            $body = str_replace(array_keys($replacements), array_values($replacements), $body);

            $mail = (new MailMessage)->subject($subject);
            foreach (explode("\n", $body) as $line) {
                $mail->line($line ?: ' ');
            }
            return $mail->action('Reset Password', $resetUrl);
        }

        // Default
        return (new MailMessage)
            ->subject('Reset Your Password — MoBilling')
            ->greeting("Hello {$notifiable->name},")
            ->line('We received a request to reset your password.')
            ->action('Reset Password', $resetUrl)
            ->line('This link will expire in 60 minutes.')
            ->line('If you did not request a password reset, no action is needed.')
            ->salutation('Regards, The MoBilling Team');
    }
}
