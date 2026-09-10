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

        return "Your WiFi voucher is ready!\nUsername: {$p->hotspot_username}\nPassword: {$p->hotspot_password}\nIncludes: {$this->limitsDescription()}\nEnter these on the WiFi login page to connect.";
    }

    /**
     * Describes the plan's limit(s) instead of a fixed expiry date — the
     * router's own time limit only starts counting from first login (see
     * ProvisionWifiVoucherJob), so there's no single "valid until" date to
     * quote at issuance time.
     */
    private function limitsDescription(): string
    {
        $plan = $this->purchase->plan;
        $parts = [];

        if ($plan?->duration_value && $plan?->duration_unit) {
            $parts[] = "{$plan->duration_value} {$plan->duration_unit} of connected use, starting from your first login";
        }
        if ($plan?->data_cap_mb) {
            $gb = rtrim(rtrim(number_format($plan->data_cap_mb / 1024, 1), '0'), '.');
            $parts[] = "{$gb}GB of data";
        }

        return $parts ? implode(' + ', $parts) : 'unlimited access';
    }
}
