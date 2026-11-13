<?php

namespace App\Notifications;

use App\Channels\SmsChannel;
use App\Channels\WhatsAppChannel;
use App\Models\Tenant;
use App\Models\WifiVoucherPurchase;
use App\Services\MosmsService;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Notification;

/**
 * Delivers the hotspot username/password to the customer's phone once
 * provisioned — they typed only a phone number at checkout, so this (or
 * the on-screen status page) is the only way they get their voucher.
 *
 * Sent through MoBilling's own ("Moinfotech Company Limited") SMS/WhatsApp
 * account rather than the router-owning tenant's: most WiFi hotspot
 * tenants are small shop owners who never set up their own SMS, and this
 * is a transactional "here's your code" message, not tenant-branded
 * content, so there's nothing tenant-specific worth gating it behind.
 */
class WifiVoucherIssuedNotification extends Notification implements ShouldQueue
{
    use Queueable;

    private const SENDING_TENANT_ID = '019c8f39-679e-70d2-af92-ac72a25b0d9c';

    public function __construct(public WifiVoucherPurchase $purchase) {}

    public static function sendingTenant(): ?Tenant
    {
        return Tenant::withoutGlobalScopes()->find(self::SENDING_TENANT_ID);
    }

    /** True if the sending tenant can actually deliver SMS and/or WhatsApp right now. */
    public static function canDeliver(): bool
    {
        $tenant = self::sendingTenant();
        if (!$tenant) {
            return false;
        }

        $mosmsLinked = app(MosmsService::class)->isLinked($tenant);
        $canSms = (bool) $tenant->sms_authorization || $mosmsLinked;
        $canWhatsApp = ((bool) $tenant->whatsapp_phone_number_id && (bool) $tenant->whatsapp_access_token) || $mosmsLinked;

        return $canSms || $canWhatsApp;
    }

    public function notificationTenant(): ?Tenant
    {
        return self::sendingTenant();
    }

    public function via($notifiable): array
    {
        $tenant = $this->notificationTenant();
        if (!$tenant || !$notifiable->phone) {
            return [];
        }

        $mosmsLinked = app(MosmsService::class)->isLinked($tenant);

        $channels = [];
        if ($tenant->sms_authorization || $mosmsLinked) {
            $channels[] = SmsChannel::class;
        }
        if (($tenant->whatsapp_phone_number_id && $tenant->whatsapp_access_token) || $mosmsLinked) {
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
