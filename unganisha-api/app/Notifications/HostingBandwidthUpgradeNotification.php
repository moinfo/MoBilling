<?php

namespace App\Notifications;

use App\Models\HostingAccount;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Notification;

/** Staff heads-up: a bandwidth-suspended account was upgraded (restored, or still over the new limit). */
class HostingBandwidthUpgradeNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(public HostingAccount $hostingAccount, public bool $restored) {}

    public function via($notifiable): array
    {
        return ['database', \App\Channels\FcmChannel::class];
    }

    private function title(): string
    {
        return $this->restored ? 'Bandwidth-suspended account upgraded and reactivated' : 'Bandwidth-suspended account upgraded but still suspended';
    }

    private function message(): string
    {
        return "{$this->hostingAccount->domain}: " . ($this->restored
            ? 'the new plan brought usage under the limit and the account was reactivated.'
            : 'usage is still at or above the new limit — please review the account.');
    }

    public function toFcm($notifiable): ?array
    {
        return ['title' => $this->title(), 'body' => $this->message(), 'data' => ['type' => 'hosting_bandwidth_upgrade', 'hosting_account_id' => $this->hostingAccount->id]];
    }

    public function toArray($notifiable): array
    {
        return ['type' => 'hosting_bandwidth_upgrade', 'title' => $this->title(), 'message' => $this->message(), 'hosting_account_id' => $this->hostingAccount->id, 'url' => '/hosting'];
    }
}
