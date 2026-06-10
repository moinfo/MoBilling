<?php

namespace App\Notifications;

use App\Models\SystemVerification;
use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * Fired by the SendVerificationReminders scheduled command. Goes to a
 * staff member who has assigned systems they haven't reported on today.
 */
class VerificationReminderNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    /**
     * @param array<int, SystemVerification> $pendingSystems
     */
    public function __construct(
        public Tenant $tenant,
        public array $pendingSystems,
        public bool $isSecondReminder = false,
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
        $count = count($this->pendingSystems);
        $prefix = $this->isSecondReminder ? '🔔 Final reminder' : 'Daily reminder';
        $subject = "{$prefix}: {$count} system" . ($count === 1 ? '' : 's') . " awaiting your verification";

        $mail = (new MailMessage)
            ->subject($subject)
            ->greeting("Hi {$notifiable->name},");

        if ($this->isSecondReminder) {
            $mail->line("**Reminder #2** — bado hujakamilisha verification ya leo kwa **{$count}** system" . ($count === 1 ? '' : 's') . ".");
            $mail->line('Tafadhali kamilisha haraka kabla saa hizi:');
        } else {
            $mail->line("Una **{$count}** system" . ($count === 1 ? '' : 's') . " ambayo bado hujaweka ripoti ya leo.");
        }

        foreach ($this->pendingSystems as $sv) {
            $domain = $sv->domain_name ? " ({$sv->domain_name})" : '';
            $mail->line("• **{$sv->name}**{$domain}");
        }

        $mail->action('Submit Verification', url('/my-verifications'));
        $mail->line('Asante kwa kuendelea kuhakikisha mifumo iko sawa.');

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toDatabase($notifiable): array
    {
        return [
            'type' => 'verification_reminder',
            'second_reminder' => $this->isSecondReminder,
            'pending_count' => count($this->pendingSystems),
            'system_ids' => array_map(fn ($s) => $s->id, $this->pendingSystems),
            'url' => '/my-verifications',
        ];
    }
}
