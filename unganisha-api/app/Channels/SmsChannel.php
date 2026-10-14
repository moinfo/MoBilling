<?php

namespace App\Channels;

use App\Services\SmsService;
use Illuminate\Notifications\Notification;

class SmsChannel
{
    public function __construct(private SmsService $smsService) {}

    public function send(object $notifiable, Notification $notification): ?array
    {
        if (!method_exists($notification, 'toSms')) {
            return null;
        }

        $message = $notification->toSms($notifiable);
        if (!$message) {
            return null;
        }

        $recipient = $notifiable->phone;
        if (!$recipient) {
            return null;
        }

        $tenant = $notifiable->tenant;
        if (!$tenant) {
            return null;
        }

        // Let exceptions propagate so Laravel fires NotificationFailed (not NotificationSent).
        // The return value becomes NotificationSent::$response — LogNotification reads
        // MoSMS's own message id out of it for later delivery-status matching.
        return $this->smsService->send($tenant, $recipient, $message);
    }
}
