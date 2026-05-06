<?php

namespace App\Notifications;

use App\Models\StaffTarget;
use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class StaffTargetAssignedSupervisorNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    public function __construct(
        public Tenant $tenant,
        public StaffTarget $target,
    ) {}

    public function via($notifiable): array
    {
        return ['database'];
    }

    public function toMail($notifiable): MailMessage
    {
        $staffName     = $this->target->user->name;
        $assignedBy    = $this->target->assignedBy->name;
        $periodStart   = $this->target->period_start->format('d M Y');
        $periodEnd     = $this->target->period_end->format('d M Y');
        $criteriaCount = $this->target->criteria->count();

        $mail = (new MailMessage)
            ->subject("Target assigned to {$staffName}: {$this->target->title} — {$this->tenant->name}")
            ->greeting("Hi {$notifiable->name},")
            ->line("{$assignedBy} has assigned a new target to **{$staffName}**: **{$this->target->title}**.")
            ->line("Period: **{$periodStart}** to **{$periodEnd}**")
            ->line("This target has **{$criteriaCount}** criterion/criteria to achieve.");

        if ($this->target->description) {
            $mail->line("Description: {$this->target->description}");
        }

        $mail->action('View Target', url('/staff-targets'))
             ->line("You will be notified when {$staffName} self-reports their progress for verification.");

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toArray($notifiable): array
    {
        $staffName = $this->target->user->name;

        return [
            'type'      => 'staff_target_assigned_supervisor',
            'title'     => 'Target assigned to your staff',
            'message'   => "{$staffName} has been assigned a new target: {$this->target->title}.",
            'target_id' => $this->target->id,
            'url'       => '/staff-targets',
        ];
    }
}
