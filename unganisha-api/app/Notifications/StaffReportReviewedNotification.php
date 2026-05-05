<?php

namespace App\Notifications;

use App\Models\StaffReport;
use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class StaffReportReviewedNotification extends Notification implements ShouldQueue
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
        $reviewerName = $this->report->reviewer->name ?? 'Your supervisor';
        $typeLabel    = ucfirst($this->report->report_type);
        $period       = $this->report->period_date->format('d M Y');
        $stars        = $this->report->rating ? str_repeat('★', $this->report->rating) . str_repeat('☆', 5 - $this->report->rating) : null;

        $mail = (new MailMessage)
            ->subject("Your {$typeLabel} report has been reviewed — {$this->tenant->name}")
            ->greeting("Hi {$notifiable->name},")
            ->line("{$reviewerName} has reviewed your **{$typeLabel} report** for {$period}.");

        if ($stars) {
            $mail->line("Rating: {$stars} ({$this->report->rating}/5)");
        }

        if ($this->report->review_notes) {
            $mail->line("**Feedback:** {$this->report->review_notes}");
        }

        $mail->action('View Report', url('/staff-reports'))
             ->line('Keep up the great work!');

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toArray($notifiable): array
    {
        $typeLabel = ucfirst($this->report->report_type);
        $rating    = $this->report->rating ? " ({$this->report->rating}/5)" : '';

        return [
            'type'      => 'staff_report_reviewed',
            'title'     => "{$typeLabel} report reviewed",
            'message'   => "Your {$typeLabel} report has been reviewed{$rating}.",
            'report_id' => $this->report->id,
            'url'       => '/staff-reports',
        ];
    }
}