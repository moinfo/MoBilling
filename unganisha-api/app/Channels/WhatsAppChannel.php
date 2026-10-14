<?php

namespace App\Channels;

use App\Services\WhatsAppService;
use Illuminate\Notifications\Notification;
use Illuminate\Support\Str;

class WhatsAppChannel
{
    public function __construct(private WhatsAppService $whatsAppService) {}

    public function send(object $notifiable, Notification $notification): ?array
    {
        if (!method_exists($notification, 'toWhatsApp')) {
            return null;
        }

        // The client replied STOP to the bot: no WhatsApp reminders/notifications (their replies to messages
        // THEY start are unaffected — those never go through this channel). Security notices opt out of the opt-out.
        if ($notifiable instanceof \App\Models\Client && $notifiable->whatsappOptedOut() && !($notification->whatsappTransactional ?? false)) {
            return null;
        }

        $message = $notification->toWhatsApp($notifiable);
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

        // MoSMS sends are queued on their side, so no delivery-trackable id exists
        // yet when they respond to us — we mint this ourselves and MoSMS echoes it
        // back in its later delivery-status webhook push, which is how
        // LogNotification's logged row gets matched up with a real outcome.
        $clientRef = (string) Str::uuid();

        // $message can be a string (plain text) or an array with template info.
        // Template sends fall back to the plain-text 'fallback' when the named
        // template isn't approved/available yet — so new templates roll out
        // without ever dropping a notification.
        if (is_array($message)) {
            try {
                $this->whatsAppService->sendTemplate(
                    $tenant,
                    $recipient,
                    $message['template'],
                    $message['parameters'] ?? [],
                    $message['language'] ?? 'en',
                    $message['button_url'] ?? null,
                    $message['header_image_url'] ?? null,
                    $clientRef,
                );
            } catch (\Throwable $e) {
                $fallback = $message['fallback'] ?? null;
                if (!$fallback) {
                    throw $e;
                }
                $this->whatsAppService->sendText($tenant, $recipient, $fallback, $clientRef);
            }
        } else {
            $this->whatsAppService->sendText($tenant, $recipient, $message, $clientRef);
        }

        return ['client_ref' => $clientRef];
    }
}
