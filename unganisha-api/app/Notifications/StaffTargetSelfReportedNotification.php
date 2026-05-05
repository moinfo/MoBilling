<?php

namespace App\Notifications;

use App\Models\StaffTarget;
use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class StaffTargetSelfReportedNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    public function __construct(
        public Tenant $tenant,
        public StaffTarget $target,
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
        $staffName   = $this->target->user->name;
        $periodStart = $this->target->period_start->format('d M Y');
        $periodEnd   = $this->target->period_end->format('d M Y');

        $mail = (new MailMessage)
            ->subject("{$staffName} self-reported on target: {$this->target->title} — {$this->tenant->name}")
            ->greeting("Hi {$notifiable->name},")
            ->line("{$staffName} has self-reported their achieved values for target **{$this->target->title}**.")
            ->line("Period: {$periodStart} – {$periodEnd}")
            ->line('Please review and verify their submitted values.')
            ->action('Verify Target', url('/staff-targets'))
            ->line('Your verification will calculate the commission earned.');

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toArray($notifiable): array
    {
        $staffName = $this->target->user->name;

        return [
            'type'      => 'staff_target_self_reported',
            'title'     => 'Target awaiting verification',
            'message'   => "{$staffName} has self-reported on: {$this->target->title}.",
            'target_id' => $this->target->id,
            'url'       => '/staff-targets',
        ];
    }
}