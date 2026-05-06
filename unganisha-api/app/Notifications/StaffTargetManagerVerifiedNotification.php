<?php

namespace App\Notifications;

use App\Models\StaffTarget;
use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class StaffTargetManagerVerifiedNotification extends Notification implements ShouldQueue
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
        $staffName       = $this->target->user->name;
        $verifierName    = $this->target->verifiedBy->name ?? 'The supervisor';
        $earned          = (float) ($this->target->manager_commission_earned ?? 0);
        $earnedFmt       = number_format($earned, 2);
        $goalsMet        = $this->target->criteria->filter(fn ($c) => $c->goal_met)->count();
        $totalCriteria   = $this->target->criteria->count();
        $allMet          = $goalsMet === $totalCriteria && $totalCriteria > 0;

        $mail = (new MailMessage)
            ->subject("Manager commission update: {$this->target->title} — {$this->tenant->name}")
            ->greeting("Hi {$notifiable->name},")
            ->line("{$verifierName} has verified **{$staffName}**'s target **{$this->target->title}**.")
            ->line("Goals achieved: **{$goalsMet} / {$totalCriteria}**");

        if ($allMet && $earned > 0) {
            $mail->line("Your manager commission: **{$earnedFmt}** 🎉");
        } elseif ($allMet) {
            $mail->line("All goals were met but no manager commission was configured.");
        } else {
            $mail->line("Not all goals were met, so no manager commission was earned this period.");
        }

        if ($this->target->supervisor_notes) {
            $mail->line("Supervisor notes: {$this->target->supervisor_notes}");
        }

        $mail->action('View Target', url('/staff-targets'));

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toArray($notifiable): array
    {
        $staffName = $this->target->user->name;
        $earned    = (float) ($this->target->manager_commission_earned ?? 0);
        $msg = $earned > 0
            ? "Manager commission earned: " . number_format($earned, 2) . " on {$staffName}'s target."
            : "{$staffName}'s target was verified — no manager commission this period.";

        return [
            'type'      => 'staff_target_manager_verified',
            'title'     => 'Manager commission update',
            'message'   => $msg,
            'target_id' => $this->target->id,
            'url'       => '/staff-targets',
        ];
    }
}
