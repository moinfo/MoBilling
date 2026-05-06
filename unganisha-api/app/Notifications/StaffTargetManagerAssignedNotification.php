<?php

namespace App\Notifications;

use App\Models\StaffTarget;
use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class StaffTargetManagerAssignedNotification extends Notification implements ShouldQueue
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
        $staffName     = $this->target->user->name;
        $assignedBy    = $this->target->assignedBy->name;
        $periodStart   = $this->target->period_start->format('d M Y');
        $periodEnd     = $this->target->period_end->format('d M Y');

        $type  = $this->target->manager_commission_type;
        $value = (float) ($this->target->manager_commission_value ?? 0);
        $commissionLine = match ($type) {
            'fixed'      => "Your override commission: **fixed " . number_format($value, 2) . "** if all goals are met.",
            'percentage' => "Your override commission: **{$value}% of {$staffName}'s gross commission** if all goals are met.",
            default      => "No override commission is set for you on this target.",
        };

        $mail = (new MailMessage)
            ->subject("You're managing {$staffName}'s target: {$this->target->title} — {$this->tenant->name}")
            ->greeting("Hi {$notifiable->name},")
            ->line("{$assignedBy} has assigned you to manage **{$staffName}**'s target: **{$this->target->title}**.")
            ->line("Period: **{$periodStart}** to **{$periodEnd}**")
            ->line($commissionLine)
            ->action('View Target', url('/staff-targets'))
            ->line("Help {$staffName} hit their goals — your earnings depend on it.");

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toArray($notifiable): array
    {
        $staffName = $this->target->user->name;

        return [
            'type'      => 'staff_target_manager_assigned',
            'title'     => 'You are managing a target',
            'message'   => "You have been assigned to manage {$staffName}'s target: {$this->target->title}.",
            'target_id' => $this->target->id,
            'url'       => '/staff-targets',
        ];
    }
}
