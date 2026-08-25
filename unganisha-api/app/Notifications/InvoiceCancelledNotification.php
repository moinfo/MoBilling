<?php

namespace App\Notifications;

use App\Channels\SmsChannel;
use App\Channels\WhatsAppChannel;
use App\Models\Document;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class InvoiceCancelledNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    public function __construct(public Document $document) {}

    public function via($notifiable): array
    {
        $this->document->loadMissing(['tenant' => fn ($q) => $q->withoutGlobalScopes()]);
        $tenant = $this->document->tenant;

        $channels = [];

        if ($tenant->email_enabled && $notifiable->email) {
            $channels[] = 'mail';
        }

        if ($tenant->sms_enabled && $tenant->reminder_sms_enabled) {
            $channels[] = SmsChannel::class;
        }

        if ($tenant->whatsapp_enabled && $tenant->reminder_whatsapp_enabled) {
            $channels[] = WhatsAppChannel::class;
        }

        // Mobile push: FcmChannel no-ops when FCM_CREDENTIALS is unset and
        // when the client has no registered devices, so it is always safe on.
        $channels[] = \App\Channels\FcmChannel::class;

        return $channels;
    }

    public function toFcm($notifiable): ?array
    {
        $this->document->loadMissing(['tenant' => fn ($q) => $q->withoutGlobalScopes()]);
        $tenant = $this->document->tenant;

        return [
            'title' => "Invoice {$this->document->document_number} cancelled",
            'body'  => "Invoice {$this->document->document_number} for {$tenant->currency} "
                . number_format($this->document->total, 2) . ' has been cancelled. No payment is required.',
            'data'  => ['type' => 'invoice', 'document_id' => $this->document->id],
        ];
    }

    public function toWhatsApp($notifiable): array
    {
        $this->document->loadMissing(['tenant' => fn ($q) => $q->withoutGlobalScopes()]);
        $tenant = $this->document->tenant;
        $amount = $tenant->currency . ' ' . number_format($this->document->total, 2);

        return [
            'template' => 'invoice_cancelled_v1',
            'parameters' => [$this->document->document_number, $amount, $tenant->name],
            'language' => 'en',
            'fallback' => "❌ Invoice {$this->document->document_number} ({$amount}) has been cancelled. No payment required. — {$tenant->name}",
        ];
    }

    public function toSms($notifiable): ?string
    {
        $this->document->loadMissing(['tenant' => fn ($q) => $q->withoutGlobalScopes()]);
        $tenant = $this->document->tenant;

        return "Invoice {$this->document->document_number} for {$tenant->currency} "
            . number_format($this->document->total, 2)
            . " has been cancelled. No payment is required. — {$tenant->name}";
    }

    public function toMail($notifiable): MailMessage
    {
        $this->document->load('client');
        $this->document->loadMissing(['tenant' => fn ($q) => $q->withoutGlobalScopes()]);

        $tenant = $this->document->tenant;

        $mail = (new MailMessage)
            ->subject("Invoice {$this->document->document_number} Cancelled — {$tenant->name}")
            ->greeting("Hello {$this->document->client->name},")
            ->line("This is to inform you that invoice **{$this->document->document_number}** has been cancelled.")
            ->line("Amount: {$tenant->currency} " . number_format($this->document->total, 2))
            ->line('No payment is required for this invoice.')
            ->line('If you have any questions, please contact us.')
            ->line('Thank you.');

        $this->applyBranding($mail, $tenant);

        return $mail;
    }
}
