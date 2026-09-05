<?php

namespace App\Notifications;

use App\Models\SmsPurchase;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * `SmsPurchaseController::checkout()`'s Pesapal submission threw — the
 * purchase row exists but was marked `failed` before any payment page ever
 * showed. Fired to staff with `menu.sms`.
 */
class SmsPurchaseFailedNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(public SmsPurchase $purchase) {}

    public function via($notifiable): array
    {
        return ['database', \App\Channels\FcmChannel::class];
    }

    public function toFcm($notifiable): ?array
    {
        return [
            'title' => 'SMS purchase failed',
            'body'  => "{$this->purchase->sms_quantity} SMS ({$this->purchase->package_name}) — payment could not be started.",
            'data'  => ['type' => 'sms_purchase_failed', 'sms_purchase_id' => $this->purchase->id],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        return (new MailMessage)
            ->subject('SMS purchase failed to start')
            ->line("A purchase of {$this->purchase->sms_quantity} SMS ({$this->purchase->package_name}) could not reach the payment gateway.")
            ->action('View purchase history', url('/sms'));
    }

    public function toArray($notifiable): array
    {
        return [
            'type'    => 'sms_purchase_failed',
            'title'   => 'SMS purchase failed',
            'message' => "{$this->purchase->sms_quantity} SMS ({$this->purchase->package_name}) — payment could not be started.",
            'sms_purchase_id' => $this->purchase->id,
            'url'     => '/sms',
        ];
    }
}
