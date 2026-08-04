<?php

namespace App\Listeners;

use App\Channels\SmsChannel;
use App\Channels\WhatsAppChannel;
use App\Models\Client;
use App\Models\CommunicationLog;
use App\Models\User;
use Illuminate\Notifications\Events\NotificationSent;
use Illuminate\Support\Str;

class LogNotification
{
    public function handle(NotificationSent $event): void
    {
        $notifiable = $event->notifiable;
        $notification = $event->notification;

        // Only log actual communications (mail and SMS), skip database/broadcast
        $channel = match (true) {
            $event->channel === 'mail' => 'email',
            $event->channel === SmsChannel::class, str_contains($event->channel, 'Sms') => 'sms',
            $event->channel === WhatsAppChannel::class, str_contains($event->channel, 'WhatsApp') => 'whatsapp',
            default => null,
        };

        if (!$channel) {
            return;
        }

        // Resolve tenant_id and client_id from the notifiable
        $tenantId = null;
        $clientId = null;
        $recipient = '';

        if ($notifiable instanceof Client) {
            $tenantId = $notifiable->tenant_id;
            $clientId = $notifiable->id;
            $recipient = $channel === 'email'
                ? ($notifiable->email ?? '')
                : ($notifiable->phone ?? '');
        } elseif ($notifiable instanceof User) {
            $tenantId = $notifiable->tenant_id;
            $recipient = $channel === 'email'
                ? ($notifiable->email ?? '')
                : ($notifiable->phone ?? '');
        }

        if (!$tenantId) {
            return;
        }

        // Extract notification type as snake_case short name
        $type = Str::snake(class_basename($notification));

        // Extract subject and message
        $subject = null;
        $message = null;

        if ($channel === 'email') {
            // $event->response is SentMessage — extract subject from the actual email
            $subject = $this->extractEmailSubject($event->response);
        } elseif ($channel === 'sms') {
            // SmsChannel::send() returns void, so call toSms() to get the message
            $message = $this->extractSmsMessage($notification, $notifiable);
        } elseif ($channel === 'whatsapp') {
            $message = $this->extractWhatsAppMessage($notification, $notifiable);
        }

        // Build metadata from public properties on the notification
        $metadata = $this->extractMetadata($notification);

        CommunicationLog::withoutGlobalScopes()->create([
            'tenant_id' => $tenantId,
            'client_id' => $clientId,
            'channel' => $channel,
            'type' => $type,
            'recipient' => $recipient,
            'subject' => $subject,
            'message' => $message,
            'status' => 'sent',
            'metadata' => $metadata ?: null,
        ]);
    }

    private function extractEmailSubject($response): ?string
    {
        // Laravel wraps Symfony's SentMessage
        if ($response instanceof \Illuminate\Mail\SentMessage) {
            return $response->getOriginalMessage()->getSubject();
        }
        if ($response instanceof \Symfony\Component\Mailer\SentMessage) {
            return $response->getOriginalMessage()->getSubject();
        }

        return null;
    }

    private function extractSmsMessage($notification, $notifiable): ?string
    {
        if (method_exists($notification, 'toSms')) {
            try {
                return $notification->toSms($notifiable);
            } catch (\Throwable) {
                return null;
            }
        }

        return null;
    }

    /** toWhatsApp() returns either a plain string or a template array with a 'fallback' text. */
    private function extractWhatsAppMessage($notification, $notifiable): ?string
    {
        if (!method_exists($notification, 'toWhatsApp')) {
            return null;
        }
        try {
            $msg = $notification->toWhatsApp($notifiable);
        } catch (\Throwable) {
            return null;
        }

        if (is_array($msg)) {
            return $msg['fallback'] ?? (isset($msg['template']) ? "[{$msg['template']}]" : null);
        }

        return $msg;
    }

    private function extractMetadata($notification): array
    {
        $meta = [];

        if (property_exists($notification, 'documents') && $notification->documents) {
            $meta['document_ids'] = $notification->documents->pluck('id')->values()->all();
            $meta['bundled'] = true;
        } elseif (property_exists($notification, 'document') && $notification->document) {
            $meta['document_id'] = $notification->document->id;
        }
        if (property_exists($notification, 'bill') && $notification->bill) {
            $meta['bill_id'] = $notification->bill->id;
        }

        return $meta;
    }
}
