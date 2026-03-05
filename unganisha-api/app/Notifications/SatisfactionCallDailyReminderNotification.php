<?php

namespace App\Notifications;

use App\Channels\SmsChannel;
use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;
use Illuminate\Support\Collection;

class SatisfactionCallDailyReminderNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    public function __construct(
        public Tenant $tenant,
        public int $callCount,
        public Collection $calls,
    ) {}

    public function via($notifiable): array
    {
        $channels = ['database'];

        if ($this->tenant->email_enabled && $this->tenant->reminder_email_enabled) {
            $channels[] = 'mail';
        }

        if ($this->tenant->sms_enabled && $this->tenant->reminder_sms_enabled) {
            $channels[] = SmsChannel::class;
        }

        return $channels;
    }

    public function toMail($notifiable): MailMessage
    {
        $clientNames = $this->calls->pluck('client.name')->filter()->implode(', ');

        $mail = (new MailMessage)
            ->subject("You have {$this->callCount} satisfaction call(s) today — {$this->tenant->name}")
            ->greeting("Hi {$notifiable->name},")
            ->line("You have **{$this->callCount}** satisfaction call(s) scheduled for today.")
            ->line("Clients: {$clientNames}")
            ->action('View Satisfaction Calls', url('/satisfaction-calls'))
            ->line('Please complete these calls before end of day.');

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toSms($notifiable): string
    {
        $clientNames = $this->calls->pluck('client.name')->filter()->take(5)->implode(', ');
        $extra = $this->callCount > 5 ? " and " . ($this->callCount - 5) . " more" : "";

        return "Hi {$notifiable->name}, you have {$this->callCount} satisfaction call(s) today: {$clientNames}{$extra}. — {$this->tenant->name}";
    }

    public function toArray($notifiable): array
    {
        return [
            'type' => 'satisfaction_call_daily_reminder',
            'title' => 'Satisfaction Calls Today',
            'message' => "You have {$this->callCount} satisfaction call(s) scheduled for today.",
            'url' => '/satisfaction-calls',
        ];
    }
}
