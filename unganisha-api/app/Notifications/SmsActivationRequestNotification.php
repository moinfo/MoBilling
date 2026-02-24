<?php

namespace App\Notifications;

use App\Models\PlatformSetting;
use App\Models\Tenant;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class SmsActivationRequestNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(public Tenant $tenant) {}

    public function via($notifiable): array
    {
        return ['mail', 'database'];
    }

    public function toMail($notifiable): MailMessage
    {
        $configureUrl = config('app.frontend_url', 'http://localhost:5173') . '/admin/sms-settings?tenant=' . $this->tenant->id;

        $replacements = [
            '{tenant_name}' => $this->tenant->name,
            '{tenant_email}' => $this->tenant->email,
            '{configure_url}' => $configureUrl,
        ];

        $subject = PlatformSetting::get('sms_activation_email_subject');
        $body = PlatformSetting::get('sms_activation_email_body');

        if ($subject && $body) {
            $subject = str_replace(array_keys($replacements), array_values($replacements), $subject);
            $body = str_replace(array_keys($replacements), array_values($replacements), $body);

            $mail = (new MailMessage)->subject($subject);
            foreach (explode("\n", $body) as $line) {
                $mail->line($line ?: ' ');
            }
            return $mail->action('Configure SMS', $configureUrl);
        }

        // Default
        return (new MailMessage)
            ->subject("SMS Activation Request — {$this->tenant->name}")
            ->greeting("Hello Admin,")
            ->line("**{$this->tenant->name}** ({$this->tenant->email}) has requested SMS activation.")
            ->line("Please configure SMS settings for this tenant in the admin panel.")
            ->action('Configure SMS', $configureUrl)
            ->salutation('MoBilling System');
    }

    public function toArray($notifiable): array
    {
        return [
            'type' => 'sms_activation_request',
            'title' => 'SMS Activation Request',
            'message' => "{$this->tenant->name} ({$this->tenant->email}) has requested SMS activation.",
            'url' => '/admin/sms-settings?tenant=' . $this->tenant->id,
        ];
    }
}
