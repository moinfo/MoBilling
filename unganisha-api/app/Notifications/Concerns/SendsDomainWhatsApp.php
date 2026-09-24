<?php

namespace App\Notifications\Concerns;

use App\Channels\WhatsAppChannel;

/**
 * WhatsApp leg for the domain lifecycle notifications, so a client who only
 * has a phone is told too. Plain-text only (no template names are invented —
 * WhatsAppChannel sends a string as free text) and supplier-neutral.
 * Gated exactly like PaymentReceiptNotification: tenant whatsapp_enabled AND
 * the client has a phone.
 */
trait SendsDomainWhatsApp
{
    protected function withWhatsApp(array $channels, $notifiable): array
    {
        $tenant = $this->domain->tenant()->withoutGlobalScopes()->first();
        if ($tenant?->whatsapp_enabled && !empty($notifiable->phone)) {
            $channels[] = WhatsAppChannel::class;
        }

        return $channels;
    }

    /** Bilingual one-message text. */
    protected function waText(string $sw, string $en): string
    {
        return $sw . "\n\n" . $en;
    }

    protected function waExpiry(): string
    {
        return $this->domain->expires_at?->format('d M Y') ?? '—';
    }
}
