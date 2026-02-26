<?php

namespace App\Channels;

use App\Services\SmsService;
use Illuminate\Notifications\Notification;

class SmsChannel
{
    public function __construct(private SmsService $smsService) {}

    public function send(object $notifiable, Notification $notification): void
    {
        if (!method_exists($notification, 'toSms')) {
            return;
        }

        $message = $notification->toSms($notifiable);
        if (!$message) {
            return;
        }

        $recipient = $notifiable->phone;
        if (!$recipient) {
            return;
        }

        $tenant = $notifiable->tenant;
        if (!$tenant) {
            return;
        }

        // Let exceptions propagate so Laravel fires NotificationFailed (not NotificationSent)
        $this->smsService->send($tenant, $recipient, $message);
    }
}
