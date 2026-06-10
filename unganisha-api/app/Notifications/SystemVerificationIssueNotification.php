<?php

namespace App\Notifications;

use App\Models\SystemVerificationReport;
use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * Fired when a staff member reports an issue on their daily verification.
 * Goes to every admin in the tenant so action can be taken quickly.
 */
class SystemVerificationIssueNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    public function __construct(
        public Tenant $tenant,
        public SystemVerificationReport $report,
    ) {}

    public function via($notifiable): array
    {
        $channels = ['database'];

        if ($this->tenant->email_enabled && $this->tenant->reminder_email_enabled) {
            $channels[] = 'mail';
        }

        return $channels;
    }

    public function toMail($notifiable): MailMessage
    {
        $this->report->loadMissing('user', 'systemVerification');

        $staffName  = $this->report->user?->name ?? 'A staff member';
        $systemName = $this->report->systemVerification?->name ?? 'a system';
        $date       = $this->report->report_date->format('d M Y');
        $notes      = $this->report->notes ?: '(no details provided)';

        $mail = (new MailMessage)
            ->subject("⚠️ Verification issue reported: {$systemName} — {$this->tenant->name}")
            ->greeting("Hi {$notifiable->name},")
            ->line("**{$staffName}** flagged an issue on **{$systemName}** while checking on {$date}.")
            ->line("**Details:**")
            ->line($notes)
            ->action('Review Verification Reports', url('/system-verifications'))
            ->line('Please follow up so the system can be cleared.');

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toDatabase($notifiable): array
    {
        $this->report->loadMissing('user', 'systemVerification');

        return [
            'type' => 'system_verification_issue',
            'system_verification_id' => $this->report->system_verification_id,
            'system_name' => $this->report->systemVerification?->name,
            'report_id' => $this->report->id,
            'reporter' => $this->report->user?->name,
            'report_date' => $this->report->report_date?->format('Y-m-d'),
            'notes' => $this->report->notes,
            'url' => '/system-verifications',
        ];
    }
}
