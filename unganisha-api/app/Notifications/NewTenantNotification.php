<?php

namespace App\Notifications;

use App\Models\PlatformSetting;
use App\Models\Tenant;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class NewTenantNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(public Tenant $tenant) {}

    public function via($notifiable): array
    {
        // Push is independent of the mail/database channels; FcmChannel
        // no-ops when unconfigured or the recipient has no devices.
        return ['mail', 'database', \App\Channels\FcmChannel::class];
    }

    public function toFcm($notifiable): ?array
    {
        return [
            'title' => 'New tenant registered',
            'body'  => "{$this->tenant->name} ({$this->tenant->email}) just registered.",
            'data'  => ['type' => 'new_tenant', 'tenant_id' => $this->tenant->id],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        $url = config('app.frontend_url', 'http://localhost:5173') . '/admin/tenants';

        $replacements = [
            '{tenant_name}' => $this->tenant->name,
            '{tenant_email}' => $this->tenant->email,
            '{admin_url}' => $url,
        ];

        $subject = PlatformSetting::get('new_tenant_email_subject');
        $body = PlatformSetting::get('new_tenant_email_body');

        if ($subject && $body) {
            $subject = str_replace(array_keys($replacements), array_values($replacements), $subject);
            $body = str_replace(array_keys($replacements), array_values($replacements), $body);

            $mail = (new MailMessage)->subject($subject);
            foreach (explode("\n", $body) as $line) {
                $mail->line($line ?: ' ');
            }
            return $mail->action('View Tenants', $url);
        }

        // Default
        return (new MailMessage)
            ->subject("New Tenant Registration — {$this->tenant->name}")
            ->greeting('Hello Admin,')
            ->line("A new tenant has registered on MoBilling:")
            ->line("**{$this->tenant->name}** ({$this->tenant->email})")
            ->action('View Tenants', $url)
            ->salutation('MoBilling System');
    }

    public function toArray($notifiable): array
    {
        return [
            'type' => 'new_tenant',
            'title' => 'New Tenant Registered',
            'message' => "{$this->tenant->name} ({$this->tenant->email}) just registered.",
            'url' => '/admin/tenants',
        ];
    }
}
