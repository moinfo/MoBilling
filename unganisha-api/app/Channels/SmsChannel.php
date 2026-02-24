<?php

namespace App\Channels;

use App\Services\SmsService;
use Illuminate\Notifications\Notification;
use Illuminate\Support\Facades\Log;

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

        try {
            $this->smsService->send($tenant, $recipient, $message);
        } catch (\Throwable $e) {
            Log::error('SmsChannel failed', [
                'user_id' => $notifiable->id ?? null,
                'error' => $e->getMessage(),
            ]);
        }
    }
}
