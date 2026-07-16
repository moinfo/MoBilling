<?php

namespace App\Notifications;

use App\Models\StaffReport;
use App\Models\StaffReportReply;
use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class StaffReportReplyNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    public function __construct(
        public Tenant $tenant,
        public StaffReport $report,
        public StaffReportReply $reply,
        public string $authorName,
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
        $typeLabel = ucfirst($this->report->report_type);
        $period    = $this->report->period_date->format('d M Y');

        $mail = (new MailMessage)
            ->subject("New reply on a {$typeLabel} report — {$this->tenant->name}")
            ->greeting("Hi {$notifiable->name},")
            ->line("{$this->authorName} replied on the **{$typeLabel} report** for {$period}:")
            ->line("\"{$this->reply->message}\"")
            ->action('View & Reply', url('/staff-reports'));

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toArray($notifiable): array
    {
        $typeLabel = ucfirst($this->report->report_type);

        return [
            'type'      => 'staff_report_reply',
            'title'     => "New reply on {$typeLabel} report",
            'message'   => "{$this->authorName}: " . \Illuminate\Support\Str::limit($this->reply->message, 80),
            'report_id' => $this->report->id,
            'url'       => '/staff-reports',
        ];
    }
}
