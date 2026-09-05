<?php

namespace App\Notifications;

use App\Models\Tenant;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * The reseller balance `SmsPurchaseController::balance()` returned dropped
 * below the alert threshold. Fired to staff with `menu.sms` — throttled by
 * the caller (a 24h cache key per tenant) so this fires once a day at most,
 * not on every dashboard load that happens to poll the balance.
 */
class SmsLowBalanceNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(
        public Tenant $tenant,
        public int $balance,
    ) {}

    public function via($notifiable): array
    {
        return ['database', \App\Channels\FcmChannel::class];
    }

    public function toFcm($notifiable): ?array
    {
        return [
            'title' => 'SMS balance low',
            'body'  => "Only {$this->balance} SMS credits left — top up to keep reminders sending.",
            'data'  => ['type' => 'sms_low_balance'],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        return (new MailMessage)
            ->subject('SMS balance is running low')
            ->line("Only {$this->balance} SMS credits remain.")
            ->line('SMS reminders will stop sending once the balance reaches zero.')
            ->action('Top up SMS credits', url('/sms'));
    }

    public function toArray($notifiable): array
    {
        return [
            'type'    => 'sms_low_balance',
            'title'   => 'SMS balance low',
            'message' => "Only {$this->balance} SMS credits left — top up to keep reminders sending.",
            'url'     => '/sms',
        ];
    }
}
