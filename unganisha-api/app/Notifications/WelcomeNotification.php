<?php

namespace App\Notifications;

use App\Models\PlatformSetting;
use App\Models\Tenant;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class WelcomeNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(public Tenant $tenant) {}

    public function via($notifiable): array
    {
        return ['mail', 'database'];
    }

    public function toMail($notifiable): MailMessage
    {
        $loginUrl = config('app.frontend_url', 'http://localhost:5173') . '/login';

        $replacements = [
            '{user_name}' => $notifiable->name,
            '{company_name}' => $this->tenant->name,
            '{login_url}' => $loginUrl,
        ];

        $subject = PlatformSetting::get('welcome_email_subject');
        $body = PlatformSetting::get('welcome_email_body');

        if ($subject && $body) {
            $subject = str_replace(array_keys($replacements), array_values($replacements), $subject);
            $body = str_replace(array_keys($replacements), array_values($replacements), $body);

            $mail = (new MailMessage)->subject($subject);
            foreach (explode("\n", $body) as $line) {
                $mail->line($line ?: ' ');
            }
            return $mail->action('Go to Dashboard', $loginUrl);
        }

        // Default
        return (new MailMessage)
            ->subject('Welcome to MoBilling!')
            ->greeting("Hello {$notifiable->name},")
            ->line("Welcome to MoBilling! Your account for **{$this->tenant->name}** has been created successfully.")
            ->line('You have a **7-day free trial** to explore all features — invoicing, quotations, payment tracking, and more.')
            ->action('Go to Dashboard', $loginUrl)
            ->line('If you have any questions, just reply to this email.')
            ->salutation('Cheers, The MoBilling Team');
    }

    public function toArray($notifiable): array
    {
        return [
            'type' => 'welcome',
            'title' => 'Welcome to MoBilling!',
            'message' => "Your account for {$this->tenant->name} is ready. You have a 7-day free trial.",
            'url' => '/dashboard',
        ];
    }
}
