<?php

namespace App\Notifications;

use App\Channels\SmsChannel;
use App\Channels\WhatsAppChannel;
use App\Models\WifiVoucherPurchase;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Notification;

/**
 * Delivers the hotspot username/password to the customer's phone once
 * provisioned — they typed only a phone number at checkout, so this (or
 * the on-screen status page) is the only way they get their voucher.
 */
class WifiVoucherIssuedNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(public WifiVoucherPurchase $purchase) {}

    public function via($notifiable): array
    {
        $tenant = $this->purchase->tenant()->withoutGlobalScopes()->first();

        $channels = [];
        if ($tenant?->sms_enabled && $notifiable->phone) {
            $channels[] = SmsChannel::class;
        }
        if ($tenant?->whatsapp_enabled && $notifiable->phone) {
            $channels[] = WhatsAppChannel::class;
        }

        return $channels;
    }

    public function toSms($notifiable): ?string
    {
        return $this->message();
    }

    public function toWhatsApp($notifiable): ?string
    {
        return $this->message();
    }

    private function message(): string
    {
        $p = $this->purchase;
        $expires = $p->voucher_expires_at?->format('d M Y, H:i');

        return "Your WiFi voucher is ready!\nUsername: {$p->hotspot_username}\nPassword: {$p->hotspot_password}\nValid until: {$expires}\nEnter these on the WiFi login page to connect.";
    }
}
