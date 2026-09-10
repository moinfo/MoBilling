<?php

namespace App\Notifications;

use App\Channels\SmsChannel;
use App\Channels\WhatsAppChannel;
use App\Models\MikrotikRouter;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Notification;

/**
 * Alerts a tenant's admin(s) the moment their WiFi router's reachability
 * flips — sent only on the success<->failed transition (see
 * CheckWifiRouterHealth), never on every poll, so it doesn't spam while a
 * router stays down for hours. Exists because a dead router fails voucher
 * purchases silently otherwise: a customer pays, provisioning can't reach
 * the router, and nobody finds out until someone happens to check.
 */
class RouterStatusChangedNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(public MikrotikRouter $router, public bool $isOnline, public string $detail) {}

    public function via($notifiable): array
    {
        $tenant = $this->router->tenant()->withoutGlobalScopes()->first();

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
        if ($this->isOnline) {
            return "MoBilling: Your WiFi hotspot \"{$this->router->name}\" is back online. Voucher sales have resumed.";
        }

        return "MoBilling ALERT: Your WiFi hotspot \"{$this->router->name}\" has gone OFFLINE and cannot process voucher purchases right now ({$this->detail}). We'll text you when it's back.";
    }
}
