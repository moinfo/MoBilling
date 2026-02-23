<?php

namespace App\Notifications;

use App\Models\Bill;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class BillDueReminderNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(public Bill $bill) {}

    public function via($notifiable): array
    {
        return ['mail'];
    }

    public function toMail($notifiable): MailMessage
    {
        return (new MailMessage)
            ->subject("Bill Reminder: {$this->bill->name} — MoBilling")
            ->line("{$this->bill->name} of KES " . number_format($this->bill->amount, 2) . " is due on {$this->bill->due_date->format('d M Y')}.")
            ->line("Don't forget to pay!")
            ->action('View Bills', url('/bills'));
    }
}
