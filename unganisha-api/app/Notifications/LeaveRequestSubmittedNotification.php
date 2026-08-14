<?php

namespace App\Notifications;

use App\Models\LeaveRequest;
use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class LeaveRequestSubmittedNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    public function __construct(
        public Tenant $tenant,
        public LeaveRequest $request,
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
        $staffName = $this->request->user->name;
        $typeLabel = $this->request->leaveType->name;
        $range = $this->request->start_date->format('d M Y') . ' – ' . $this->request->end_date->format('d M Y');

        $mail = (new MailMessage)
            ->subject("Leave request from {$staffName} — {$this->tenant->name}")
            ->greeting("Hi {$notifiable->name},")
            ->line("{$staffName} has requested **{$typeLabel}** for {$range} ({$this->request->days} day(s)).");

        if ($this->request->reason) {
            $mail->line("**Reason:** {$this->request->reason}");
        }

        $mail->action('Review Request', url('/leave'))
             ->line('Please approve or reject it at your earliest convenience.');

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toArray($notifiable): array
    {
        $staffName = $this->request->user->name;
        $typeLabel = $this->request->leaveType->name;

        return [
            'type' => 'leave_request_submitted',
            'title' => 'Leave request submitted',
            'message' => "{$staffName} requested {$typeLabel} ({$this->request->days} day(s)).",
            'leave_request_id' => $this->request->id,
            'url' => '/leave',
        ];
    }
}
