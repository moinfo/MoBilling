<?php

namespace App\Notifications;

use App\Models\Document;
use App\Models\HostingAccount;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Notification;

/**
 * Staff heads-up for the "upgrade now, pay later" flow (bandwidth-suspended accounts):
 * kind = applied (upgrade applied before payment) | unpaid (still unpaid past the due date) | reverted.
 */
class HostingPayLaterUpgradeNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(
        public HostingAccount $hostingAccount,
        public string $kind,
        public ?Document $document = null,
        public ?string $clientName = null,
        public ?string $dueDate = null,
    ) {}

    public function via($notifiable): array
    {
        return ['database', \App\Channels\FcmChannel::class];
    }

    private function title(): string
    {
        return match ($this->kind) {
            'unpaid'   => 'Upgrade still unpaid after the due date',
            'reverted' => 'Upgrade applied before payment was reverted',
            default    => 'Upgrade applied before payment',
        };
    }

    private function message(): string
    {
        $inv = $this->document ? "invoice {$this->document->document_number}" : 'the upgrade invoice';
        $who = $this->clientName ? " ({$this->clientName})" : '';
        return match ($this->kind) {
            'unpaid'   => "{$this->hostingAccount->domain}{$who}: {$inv} is unpaid past its due date ({$this->dueDate}). Nothing was reverted automatically; contact the client or use 'Revert pay-later upgrade'.",
            'reverted' => "{$this->hostingAccount->domain}{$who}: the plan was restored to the previous one; {$inv} was cancelled. Please review the account state.",
            default    => "{$this->hostingAccount->domain}{$who}: upgraded before payment. Upgrade pending payment (due {$this->dueDate}), {$inv}.",
        };
    }

    public function toFcm($notifiable): ?array
    {
        return ['title' => $this->title(), 'body' => $this->message(), 'data' => ['type' => 'hosting_pay_later_upgrade', 'hosting_account_id' => $this->hostingAccount->id]];
    }

    public function toArray($notifiable): array
    {
        return ['type' => 'hosting_pay_later_upgrade', 'title' => $this->title(), 'message' => $this->message(),
            'hosting_account_id' => $this->hostingAccount->id, 'document_id' => $this->document?->id, 'url' => '/hosting'];
    }
}
