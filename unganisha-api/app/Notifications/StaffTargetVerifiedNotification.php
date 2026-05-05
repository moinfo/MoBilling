<?php

namespace App\Notifications;

use App\Models\StaffTarget;
use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class StaffTargetVerifiedNotification extends Notification implements ShouldQueue
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
        $verifierName     = $this->target->verifiedBy->name ?? 'Your supervisor';
        $totalCommission  = number_format($this->target->totalCommissionEarned(), 2);
        $hasCommission    = $this->target->totalCommissionEarned() > 0;
        $goalsMet         = $this->target->criteria->filter(fn ($c) => $c->goal_met)->count();
        $totalCriteria    = $this->target->criteria->count();

        $mail = (new MailMessage)
            ->subject("Target verified: {$this->target->title} — {$this->tenant->name}")
            ->greeting("Hi {$notifiable->name},")
            ->line("{$verifierName} has verified your target **{$this->target->title}**.")
            ->line("Goals achieved: **{$goalsMet} / {$totalCriteria}**");

        if ($hasCommission) {
            $mail->line("Commission earned: **KES {$totalCommission}** 🎉");
        } else {
            $mail->line("No commission was earned for this target period.");
        }

        if ($this->target->supervisor_notes) {
            $mail->line("Supervisor notes: {$this->target->supervisor_notes}");
        }

        $mail->action('View Target', url('/staff-targets'))
             ->line('Keep pushing towards your goals!');

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toArray($notifiable): array
    {
        $totalCommission = $this->target->totalCommissionEarned();
        $commissionText  = $totalCommission > 0
            ? ' Commission: KES ' . number_format($totalCommission, 2) . '.'
            : '';

        return [
            'type'      => 'staff_target_verified',
            'title'     => 'Target verified',
            'message'   => "Your target \"{$this->target->title}\" has been verified.{$commissionText}",
            'target_id' => $this->target->id,
            'url'       => '/staff-targets',
        ];
    }
}