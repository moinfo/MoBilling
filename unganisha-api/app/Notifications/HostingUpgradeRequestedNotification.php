<?php

namespace App\Notifications;

use App\Models\Document;
use App\Models\HostingAccount;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * A client changed their own hosting plan from the portal
 * (`PortalHostingController::upgrade`) — silent before this, whether the
 * change applied immediately (no invoice) or needs a prorated invoice paid
 * first. Fired to staff with `hosting.change_package`.
 */
class HostingUpgradeRequestedNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(
        public HostingAccount $hostingAccount,
        public string $summary,
        public ?Document $document = null,
    ) {}

    public function via($notifiable): array
    {
        return ['database', \App\Channels\FcmChannel::class];
    }

    public function toFcm($notifiable): ?array
    {
        return [
            'title' => 'Hosting plan change requested',
            'body'  => "{$this->hostingAccount->domain}: {$this->summary}",
            'data'  => [
                'type' => 'hosting_upgrade',
                'hosting_account_id' => $this->hostingAccount->id,
            ],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        $mail = (new MailMessage)
            ->subject("Hosting plan change — {$this->hostingAccount->domain}")
            ->line("{$this->hostingAccount->domain}: {$this->summary}");

        if ($this->document) {
            $mail->line("Invoice {$this->document->document_number} must be paid before it takes effect.")
                ->action('View invoice', url("/invoices?preview={$this->document->id}"));
        } else {
            $mail->line('No charge — the change has already been applied.')
                ->action('View hosting account', url('/hosting'));
        }

        return $mail;
    }

    public function toArray($notifiable): array
    {
        return [
            'type'    => 'hosting_upgrade',
            'title'   => 'Hosting plan change requested',
            'message' => "{$this->hostingAccount->domain}: {$this->summary}",
            'hosting_account_id' => $this->hostingAccount->id,
            'url'     => '/hosting',
        ];
    }
}
