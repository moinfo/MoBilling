<?php

namespace App\Notifications;

use App\Channels\SmsChannel;
use App\Models\Bill;
use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use App\Services\ReminderTemplateService;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class BillDueReminderNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    public function __construct(
        public Bill $bill,
        public Tenant $tenant,
    ) {}

    public function via($notifiable): array
    {
        $channels = [];

        $channels[] = 'database';

        if ($this->tenant->reminder_email_enabled) {
            $channels[] = 'mail';
        }

        if ($this->tenant->sms_enabled && $this->tenant->reminder_sms_enabled) {
            $channels[] = SmsChannel::class;
        }

        return $channels;
    }

    public function toMail($notifiable): MailMessage
    {
        $renderer = app(ReminderTemplateService::class);

        $subject = $this->tenant->reminder_email_subject
            ? $renderer->render($this->tenant->reminder_email_subject, $this->bill, $this->tenant)
            : "Bill Reminder: {$this->bill->name} — {$this->tenant->name}";

        $body = $this->tenant->reminder_email_body
            ? $renderer->render($this->tenant->reminder_email_body, $this->bill, $this->tenant)
            : "{$this->bill->name} of {$this->tenant->currency} " . number_format($this->bill->amount, 2) . " is due on {$this->bill->due_date->format('d M Y')}. Don't forget to pay!";

        $mail = (new MailMessage)
            ->subject($subject)
            ->line($body)
            ->action('View Bills', url('/bills'));

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toSms($notifiable): ?string
    {
        $renderer = app(ReminderTemplateService::class);

        $template = $this->tenant->reminder_sms_body
            ?? '{bill_name} of {currency} {amount} is due on {due_date}. Please pay on time.';

        return $renderer->render($template, $this->bill, $this->tenant);
    }

    public function toArray($notifiable): array
    {
        return [
            'type' => 'bill_due_reminder',
            'title' => 'Bill Due Reminder',
            'message' => "{$this->bill->name} of {$this->tenant->currency} " . number_format($this->bill->amount, 2) . " is due on {$this->bill->due_date->format('d M Y')}.",
            'url' => '/bills',
        ];
    }
}
