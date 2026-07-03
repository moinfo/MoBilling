<?php

namespace App\Notifications;

use App\Models\Ticket;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/** Sent to the client when staff reply to (or close) their ticket. */
class TicketRepliedNotification extends Notification
{
    use Queueable, HasTenantBranding;

    public function __construct(public Ticket $ticket, public string $replyExcerpt, public bool $closed = false) {}

    public function via($notifiable): array
    {
        return ['mail'];
    }

    public function toMail($notifiable): MailMessage
    {
        $mail = (new MailMessage)
            ->subject("[{$this->ticket->ticket_number}] {$this->ticket->subject}" . ($this->closed ? ' — closed' : ' — new reply'))
            ->greeting("Hello {$notifiable->name},")
            ->line($this->closed
                ? "Your support ticket has been closed. You can reopen it any time by replying in the portal."
                : "Our team has replied to your support ticket:")
            ->line('"' . \Illuminate\Support\Str::limit($this->replyExcerpt, 300) . '"')
            ->line("View the full conversation and reply in your client portal → Support Tickets.");

        return $this->applyBranding($mail, $this->ticket->tenant);
    }
}
