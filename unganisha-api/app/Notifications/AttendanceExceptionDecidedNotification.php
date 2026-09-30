<?php

namespace App\Notifications;

use App\Models\AttendanceExceptionRequest;
use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class AttendanceExceptionDecidedNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    public function __construct(
        public Tenant $tenant,
        public AttendanceExceptionRequest $request,
    ) {}

    public function via($notifiable): array
    {
        $channels = ['database'];

        if ($this->tenant->email_enabled && $this->tenant->reminder_email_enabled) {
            $channels[] = 'mail';
        }

        $channels[] = \App\Channels\FcmChannel::class;

        return $channels;
    }

    private function verb(): string
    {
        return $this->request->status === 'approved' ? 'approved' : 'rejected';
    }

    public function toFcm($notifiable): ?array
    {
        return [
            'title' => "Attendance explanation {$this->verb()}",
            'body'  => "Your explanation for {$this->request->date->format('d M')} was {$this->verb()}.",
            'data'  => ['type' => 'attendance_exception', 'attendance_exception_id' => $this->request->id],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        $reviewerName = $this->request->reviewer->name ?? 'Your supervisor';

        $mail = (new MailMessage)
            ->subject("Your attendance explanation was {$this->verb()} — {$this->tenant->name}")
            ->greeting("Hi {$notifiable->name},")
            ->line("{$reviewerName} has {$this->verb()} your explanation for {$this->request->date->format('d M Y')}.");

        if ($this->request->review_note) {
            $mail->line("**Note:** {$this->request->review_note}");
        }

        $mail->action('View', url('/attendance'));

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toArray($notifiable): array
    {
        return [
            'type' => 'attendance_exception_decided',
            'title' => "Attendance explanation {$this->verb()}",
            'message' => "Your explanation for {$this->request->date->format('d M')} was {$this->verb()}.",
            'attendance_exception_id' => $this->request->id,
            'url' => '/attendance',
        ];
    }
}
