<?php

namespace App\Notifications;

use App\Models\LeaveRequest;
use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class LeaveRequestDecidedNotification extends Notification implements ShouldQueue
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

        // Push is independent of the tenant's channel settings; FcmChannel
        // no-ops when unconfigured or the user has no devices.
        $channels[] = \App\Channels\FcmChannel::class;

        return $channels;
    }

    public function toFcm($notifiable): ?array
    {
        $typeLabel = $this->request->leaveType->name;
        $verb = $this->request->status === 'approved' ? 'approved' : 'rejected';

        return [
            'title' => "Leave request {$verb}",
            'body'  => "Your {$typeLabel} request was {$verb}.",
            'data'  => ['type' => 'leave_request', 'leave_request_id' => $this->request->id],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        $reviewerName = $this->request->reviewer->name ?? 'Your supervisor';
        $typeLabel = $this->request->leaveType->name;
        $range = $this->request->start_date->format('d M Y') . ' – ' . $this->request->end_date->format('d M Y');
        $verb = $this->request->status === 'approved' ? 'approved' : 'rejected';

        $mail = (new MailMessage)
            ->subject("Your leave request was {$verb} — {$this->tenant->name}")
            ->greeting("Hi {$notifiable->name},")
            ->line("{$reviewerName} has {$verb} your **{$typeLabel}** request for {$range}.");

        if ($this->request->review_note) {
            $mail->line("**Note:** {$this->request->review_note}");
        }

        $mail->action('View Request', url('/leave'));

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toArray($notifiable): array
    {
        $typeLabel = $this->request->leaveType->name;
        $verb = $this->request->status === 'approved' ? 'approved' : 'rejected';

        return [
            'type' => 'leave_request_decided',
            'title' => "Leave request {$verb}",
            'message' => "Your {$typeLabel} request was {$verb}.",
            'leave_request_id' => $this->request->id,
            'url' => '/leave',
        ];
    }
}
