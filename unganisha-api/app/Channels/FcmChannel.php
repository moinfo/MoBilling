<?php

namespace App\Channels;

use App\Services\FcmService;
use Illuminate\Notifications\Notification;

/**
 * Notification channel for mobile push.
 *
 * A notification opts in by returning FcmChannel::class from via() and
 * implementing toFcm($notifiable): ?array with 'title', 'body' and an
 * optional 'data' map (string values; used by the app for deep-linking).
 * Returning null from toFcm skips the push.
 */
class FcmChannel
{
    public function __construct(private FcmService $fcm) {}

    public function send(object $notifiable, Notification $notification): void
    {
        if (!$this->fcm->isConfigured() || !method_exists($notification, 'toFcm')) {
            return;
        }

        $payload = $notification->toFcm($notifiable);
        if (!$payload || empty($payload['title'])) {
            return;
        }

        $this->fcm->sendTo(
            $notifiable,
            $payload['title'],
            $payload['body'] ?? '',
            $payload['data'] ?? []
        );
    }
}
