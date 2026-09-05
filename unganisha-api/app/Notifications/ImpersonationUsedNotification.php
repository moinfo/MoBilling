<?php

namespace App\Notifications;

use App\Models\User;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * `UserController::impersonate` was used — one staff member signed in as
 * another. Already permission-gated (`settings.users`) and self/inactive
 * are rejected server-side, so this is audit visibility on a legitimate
 * action, not a security block. Fired to the tenant's OTHER `settings.users`
 * holders — the actor doesn't need to be told about their own action, and
 * whoever they signed in as isn't notified either (avoids alarming someone
 * over routine support access, mirroring how the web app itself gives no
 * indication to the impersonated account).
 */
class ImpersonationUsedNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(
        public User $actor,
        public User $target,
    ) {}

    public function via($notifiable): array
    {
        return ['database', \App\Channels\FcmChannel::class];
    }

    public function toFcm($notifiable): ?array
    {
        return [
            'title' => 'Staff impersonation used',
            'body'  => "{$this->actor->name} signed in as {$this->target->name}",
            'data'  => ['type' => 'impersonation_used'],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        return (new MailMessage)
            ->subject('Staff impersonation used')
            ->line("{$this->actor->name} signed in as {$this->target->name}.")
            ->action('Manage team', url('/team'));
    }

    public function toArray($notifiable): array
    {
        return [
            'type'    => 'impersonation_used',
            'title'   => 'Staff impersonation used',
            'message' => "{$this->actor->name} signed in as {$this->target->name}.",
            'url'     => '/team',
        ];
    }
}
