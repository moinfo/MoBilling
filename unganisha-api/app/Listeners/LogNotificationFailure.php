<?php

namespace App\Listeners;

use App\Channels\SmsChannel;
use App\Models\Client;
use App\Models\CommunicationLog;
use App\Models\User;
use Illuminate\Notifications\Events\NotificationFailed;
use Illuminate\Support\Str;

class LogNotificationFailure
{
    public function handle(NotificationFailed $event): void
    {
        $notifiable = $event->notifiable;
        $notification = $event->notification;

        // Only log actual communications (mail and SMS), skip database/broadcast
        $channel = match (true) {
            $event->channel === 'mail' => 'email',
            $event->channel === SmsChannel::class, str_contains($event->channel, 'Sms') => 'sms',
            default => null,
        };

        if (!$channel) {
            return;
        }

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

        $type = Str::snake(class_basename($notification));

        // Extract error from event data
        $error = is_array($event->data) ? ($event->data['message'] ?? json_encode($event->data)) : (string) $event->data;

        $metadata = [];
        if (property_exists($notification, 'document') && $notification->document) {
            $metadata['document_id'] = $notification->document->id;
        }
        if (property_exists($notification, 'bill') && $notification->bill) {
            $metadata['bill_id'] = $notification->bill->id;
        }

        CommunicationLog::withoutGlobalScopes()->create([
            'tenant_id' => $tenantId,
            'client_id' => $clientId,
            'channel' => $channel,
            'type' => $type,
            'recipient' => $recipient,
            'subject' => null,
            'message' => null,
            'status' => 'failed',
            'error' => $error,
            'metadata' => $metadata ?: null,
        ]);
    }
}
