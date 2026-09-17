<?php

namespace App\Notifications;

use App\Models\SystemRecord;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/** Sent to every tenant user with system_records.reconcile when a new deposit is logged, so the SMS/statement checkers know there's one waiting. */
class SystemRecordNeedsReconciliationNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(public SystemRecord $record) {}

    public function via($notifiable): array
    {
        return ['mail', 'database'];
    }

    public function toMail($notifiable): MailMessage
    {
        $url = config('app.frontend_url', 'http://localhost:5173') . '/system-records';
        $this->record->loadMissing(['system', 'systemProperty']);

        return (new MailMessage)
            ->subject('New deposit needs reconciliation')
            ->greeting('Hello,')
            ->line("A new deposit has been recorded and needs SMS + bank statement confirmation.")
            ->line("System: {$this->record->system?->name} — {$this->record->systemProperty?->name}")
            ->line('Amount: TZS ' . number_format((float) $this->record->amount, 2))
            ->line('Reference: ' . ($this->record->transaction_reference ?? '—'))
            ->action('Reconcile Now', $url)
            ->salutation('MoBilling System');
    }

    public function toArray($notifiable): array
    {
        return [
            'type'    => 'system_record_needs_reconciliation',
            'title'   => 'Deposit Needs Reconciliation',
            'message' => 'TZS ' . number_format((float) $this->record->amount, 2) . ' deposit awaiting SMS + statement confirmation.',
            'url'     => '/system-records',
        ];
    }
}
