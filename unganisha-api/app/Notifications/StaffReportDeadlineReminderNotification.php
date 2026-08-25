<?php

namespace App\Notifications;

use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use App\Channels\SmsChannel;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class StaffReportDeadlineReminderNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    public function __construct(
        public Tenant $tenant,
        public string $reportType,
        public string $periodLabel,
        public string $deadlineTime,
    ) {}

    public function via($notifiable): array
    {
        $channels = ['database'];

        if ($this->tenant->email_enabled && $this->tenant->reminder_email_enabled) {
            $channels[] = 'mail';
        }

        if ($this->tenant->sms_enabled && $this->tenant->reminder_sms_enabled) {
            $channels[] = SmsChannel::class;
        }

        // Push is independent of the tenant's channel settings; FcmChannel
        // no-ops when unconfigured or the user has no devices.
        $channels[] = \App\Channels\FcmChannel::class;

        return $channels;
    }

    public function toFcm($notifiable): ?array
    {
        $typeLabel = ucfirst($this->reportType);

        return [
            'title' => "{$typeLabel} report due today",
            'body'  => "Your {$typeLabel} report for {$this->periodLabel} is due today by {$this->deadlineTime}.",
            'data'  => ['type' => 'staff_report', 'report_type' => $this->reportType, 'period_label' => $this->periodLabel],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        $typeLabel = ucfirst($this->reportType);

        $mail = (new MailMessage)
            ->subject("{$typeLabel} report due today — {$this->tenant->name}")
            ->greeting("Hi {$notifiable->name},")
            ->line("This is a reminder that your **{$typeLabel} report** for **{$this->periodLabel}** is due today by **{$this->deadlineTime}**.")
            ->action('Submit Report', url('/staff-reports'))
            ->line('Please submit before the deadline to avoid a late mark.');

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toSms($notifiable): string
    {
        $typeLabel = ucfirst($this->reportType);
        return "Hi {$notifiable->name}, your {$typeLabel} report for {$this->periodLabel} is due today by {$this->deadlineTime}. Please submit now. — {$this->tenant->name}";
    }

    public function toArray($notifiable): array
    {
        $typeLabel = ucfirst($this->reportType);

        return [
            'type'    => 'staff_report_deadline_reminder',
            'title'   => "{$typeLabel} report due today",
            'message' => "Your {$typeLabel} report for {$this->periodLabel} is due by {$this->deadlineTime}.",
            'url'     => '/staff-reports',
        ];
    }
}