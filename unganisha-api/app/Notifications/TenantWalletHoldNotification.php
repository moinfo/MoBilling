<?php

namespace App\Notifications;

use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Notification;

/** A reseller tenant's own order is held — wallet couldn't cover it (or its cost isn't set yet). */
class TenantWalletHoldNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(
        public string $itemLabel,
        public string $reason, // 'insufficient_balance' | 'unknown_cost'
        public ?float $amountNeeded = null,
        public ?float $currentBalance = null,
    ) {}

    public function via($notifiable): array
    {
        return ['database', \App\Channels\FcmChannel::class];
    }

    private function message(): string
    {
        if ($this->reason === 'unknown_cost') {
            return "{$this->itemLabel} is on hold — its wholesale cost hasn't been set up yet. Please contact support.";
        }

        return "{$this->itemLabel} is on hold — wallet balance TZS " . number_format((float) $this->currentBalance, 2)
            . ' is short of the TZS ' . number_format((float) $this->amountNeeded, 2) . ' needed. Top up your wallet to proceed.';
    }

    public function toFcm($notifiable): ?array
    {
        return [
            'title' => 'Order on hold — wallet',
            'body'  => $this->message(),
            'data'  => ['type' => 'tenant_wallet_hold', 'reason' => $this->reason],
        ];
    }

    public function toArray($notifiable): array
    {
        return [
            'type'    => 'tenant_wallet_hold',
            'title'   => 'Order on hold — wallet',
            'message' => $this->message(),
            'reason'  => $this->reason,
        ];
    }
}
