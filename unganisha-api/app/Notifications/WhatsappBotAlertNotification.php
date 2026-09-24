<?php

namespace App\Notifications;

use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * Staff heads-up about the WhatsApp self-service bot: it can't send (e.g. MoSMS WhatsApp
 * balance exhausted), or a client sent media the bot can't handle (a bank receipt / photo).
 * Same channels as the other business-event notifications (database + FCM).
 */
class WhatsappBotAlertNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(
        public string $kind,      // 'send_failed' | 'media_received'
        public string $title,
        public string $message,
        public string $url = '/',
    ) {}

    public function via($notifiable): array
    {
        return ['database', \App\Channels\FcmChannel::class];
    }

    public function toFcm($notifiable): ?array
    {
        return ['title' => $this->title, 'body' => $this->message, 'data' => ['type' => 'whatsapp_bot_' . $this->kind]];
    }

    public function toMail($notifiable): MailMessage
    {
        return (new MailMessage)->subject($this->title)->line($this->message);
    }

    public function toArray($notifiable): array
    {
        return ['type' => 'whatsapp_bot_' . $this->kind, 'title' => $this->title, 'message' => $this->message, 'url' => $this->url];
    }
}
