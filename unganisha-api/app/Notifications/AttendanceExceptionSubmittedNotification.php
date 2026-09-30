<?php

namespace App\Notifications;

use App\Models\AttendanceExceptionRequest;
use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class AttendanceExceptionSubmittedNotification extends Notification implements ShouldQueue
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

    private function typeLabel(): string
    {
        return $this->request->type === 'field' ? 'nje ya kazi' : 'ruhusa';
    }

    public function toFcm($notifiable): ?array
    {
        $staffName = $this->request->user->name;

        return [
            'title' => 'Attendance explanation submitted',
            'body'  => "{$staffName} explained {$this->request->date->format('d M')} as {$this->typeLabel()}.",
            'data'  => ['type' => 'attendance_exception', 'attendance_exception_id' => $this->request->id],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        $staffName = $this->request->user->name;

        $mail = (new MailMessage)
            ->subject("Attendance explanation from {$staffName} — {$this->tenant->name}")
            ->greeting("Hi {$notifiable->name},")
            ->line("{$staffName} has explained {$this->request->date->format('d M Y')} as **{$this->typeLabel()}**.")
            ->line("**Comment:** {$this->request->comment}")
            ->action('Review', url('/attendance'))
            ->line('Please approve or reject it.');

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toArray($notifiable): array
    {
        $staffName = $this->request->user->name;

        return [
            'type' => 'attendance_exception_submitted',
            'title' => 'Attendance explanation submitted',
            'message' => "{$staffName} explained {$this->request->date->format('d M')} as {$this->typeLabel()}.",
            'attendance_exception_id' => $this->request->id,
            'url' => '/attendance',
        ];
    }
}
