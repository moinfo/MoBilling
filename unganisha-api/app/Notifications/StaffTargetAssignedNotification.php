<?php

namespace App\Notifications;

use App\Models\StaffTarget;
use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class StaffTargetAssignedNotification extends Notification implements ShouldQueue
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

        // Push is independent of the tenant's channel settings; FcmChannel
        // no-ops when unconfigured or the user has no devices.
        $channels[] = \App\Channels\FcmChannel::class;

        return $channels;
    }

    public function toFcm($notifiable): ?array
    {
        return [
            'title' => 'New target assigned',
            'body'  => "You have been assigned a new target: {$this->target->title}.",
            'data'  => ['type' => 'staff_target', 'staff_target_id' => $this->target->id],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        $assignedBy  = $this->target->assignedBy->name;
        $periodStart = $this->target->period_start->format('d M Y');
        $periodEnd   = $this->target->period_end->format('d M Y');
        $criteriaCount = $this->target->criteria->count();

        $mail = (new MailMessage)
            ->subject("New target assigned: {$this->target->title} — {$this->tenant->name}")
            ->greeting("Hi {$notifiable->name},")
            ->line("{$assignedBy} has assigned you a new target: **{$this->target->title}**.")
            ->line("Period: **{$periodStart}** to **{$periodEnd}**")
            ->line("This target has **{$criteriaCount}** criterion/criteria to achieve.");

        if ($this->target->description) {
            $mail->line("Description: {$this->target->description}");
        }

        $mail->action('View Target', url('/staff-targets'))
             ->line('Good luck — you can do it!');

        $supervisor = $notifiable->supervisor;
        if ($supervisor && $supervisor->id !== $notifiable->id && filter_var($supervisor->email, FILTER_VALIDATE_EMAIL)) {
            $mail->cc($supervisor->email, $supervisor->name);
        }

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toArray($notifiable): array
    {
        return [
            'type'      => 'staff_target_assigned',
            'title'     => 'New target assigned',
            'message'   => "You have been assigned a new target: {$this->target->title}.",
            'target_id' => $this->target->id,
            'url'       => '/staff-targets',
        ];
    }
}