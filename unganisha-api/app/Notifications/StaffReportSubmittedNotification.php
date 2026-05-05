<?php

namespace App\Notifications;

use App\Models\StaffReport;
use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class StaffReportSubmittedNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    public function __construct(
        public Tenant $tenant,
        public StaffReport $report,
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
        $staffName  = $this->report->user->name;
        $typeLabel  = ucfirst($this->report->report_type);
        $period     = $this->report->period_date->format('d M Y');
        $late       = $this->report->is_late ? ' ⚠️ (submitted late)' : '';

        $mail = (new MailMessage)
            ->subject("{$typeLabel} report submitted by {$staffName} — {$this->tenant->name}")
            ->greeting("Hi {$notifiable->name},")
            ->line("{$staffName} has submitted their **{$typeLabel} report** for {$period}{$late}.")
            ->line('Please review it at your earliest convenience.')
            ->action('Review Report', url('/staff-reports'))
            ->line('Thank you for keeping your team on track.');

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toArray($notifiable): array
    {
        $staffName = $this->report->user->name;
        $typeLabel = ucfirst($this->report->report_type);

        return [
            'type'      => 'staff_report_submitted',
            'title'     => "{$typeLabel} report submitted",
            'message'   => "{$staffName} submitted their {$typeLabel} report.",
            'report_id' => $this->report->id,
            'url'       => '/staff-reports',
        ];
    }
}