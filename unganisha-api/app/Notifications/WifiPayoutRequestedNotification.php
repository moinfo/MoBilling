<?php

namespace App\Notifications;

use App\Models\Tenant;
use App\Models\User;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/** Sent to MoInfoTech superadmins when a tenant taps "Request Payout" on their WiFi earnings page. */
class WifiPayoutRequestedNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(public ?Tenant $tenant, public float $amount, public User $requestedBy) {}

    public function via($notifiable): array
    {
        return ['mail', 'database'];
    }

    public function toMail($notifiable): MailMessage
    {
        $url = config('app.frontend_url', 'http://localhost:5173') . '/admin/wifi-settlements';

        return (new MailMessage)
            ->subject("WiFi payout requested — {$this->tenant?->name}")
            ->greeting('Hello Admin,')
            ->line("{$this->requestedBy->name} at {$this->tenant?->name} has requested payout of their WiFi voucher earnings.")
            ->line("Amount owed: TZS " . number_format($this->amount, 2))
            ->action('Review & Settle', $url)
            ->salutation('MoBilling System');
    }

    public function toArray($notifiable): array
    {
        return [
            'type'    => 'wifi_payout_requested',
            'title'   => 'WiFi Payout Requested',
            'message' => "{$this->tenant?->name} requested payout of TZS " . number_format($this->amount, 2),
            'url'     => '/admin/wifi-settlements',
        ];
    }
}
