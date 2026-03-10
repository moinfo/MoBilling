<?php

namespace App\Channels;

use App\Services\WhatsAppService;
use Illuminate\Notifications\Notification;

class WhatsAppChannel
{
    public function __construct(private WhatsAppService $whatsAppService) {}

    public function send(object $notifiable, Notification $notification): void
    {
        if (!method_exists($notification, 'toWhatsApp')) {
            return;
        }

        $message = $notification->toWhatsApp($notifiable);
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

        // $message can be a string (plain text) or an array with template info
        if (is_array($message)) {
            $this->whatsAppService->sendTemplate(
                $tenant,
                $recipient,
                $message['template'],
                $message['parameters'] ?? [],
                $message['language'] ?? 'en',
            );
        } else {
            $this->whatsAppService->sendText($tenant, $recipient, $message);
        }
    }
}
