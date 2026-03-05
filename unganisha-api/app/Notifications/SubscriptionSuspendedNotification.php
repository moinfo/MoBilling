<?php

namespace App\Notifications;

use App\Channels\SmsChannel;
use App\Models\ClientSubscription;
use App\Models\Document;
use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class SubscriptionSuspendedNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    public function __construct(
        public ClientSubscription $subscription,
        public Document $document,
        public Tenant $tenant,
    ) {}

    public function via($notifiable): array
    {
        $channels = [];

        if ($this->tenant->email_enabled) {
            $channels[] = 'mail';
        }

        if ($this->tenant->sms_enabled) {
            $channels[] = SmsChannel::class;
        }

        return $channels;
    }

    public function toMail($notifiable): MailMessage
    {
        $label = $this->subscription->label;
        $docNumber = $this->document->document_number;
        $currency = $this->tenant->currency;
        $totalFormatted = number_format($this->document->total, 2);

        $mail = (new MailMessage)
            ->subject("Service Suspended — Unpaid Invoice {$docNumber}")
            ->greeting("Hello {$notifiable->name},")
            ->line("Your service **{$label}** has been suspended due to unpaid invoice {$docNumber} ({$currency} {$totalFormatted}).")
            ->line('Please settle the outstanding invoice to reactivate your service.')
            ->line('If you have already made payment, please contact us with your payment reference.')
            ->line('Thank you.');

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toSms($notifiable): ?string
    {
        $label = $this->subscription->label;
        $docNumber = $this->document->document_number;

        return "{$label} suspended due to unpaid invoice {$docNumber}. Pay to reactivate. — {$this->tenant->name}";
    }
}
