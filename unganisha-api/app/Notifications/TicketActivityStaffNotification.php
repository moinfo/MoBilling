<?php

namespace App\Notifications;

use App\Models\Ticket;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/** Sent to staff (assignee or ticket managers) on new ticket / client reply. */
class TicketActivityStaffNotification extends Notification
{
    use Queueable;

    public function __construct(public Ticket $ticket, public string $event) {} // opened|client_reply

    public function via($notifiable): array
    {
        return ['database', 'mail'];
    }

    public function toDatabase($notifiable): array
    {
        return [
            'title'   => $this->event === 'opened' ? 'New support ticket' : 'Client replied to ticket',
            'message' => "{$this->ticket->ticket_number} — {$this->ticket->subject} ({$this->ticket->client?->name})",
            'link'    => '/tickets',
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        $verb = $this->event === 'opened' ? 'opened a new support ticket' : 'replied to a support ticket';

        return (new MailMessage)
            ->subject("[{$this->ticket->ticket_number}] {$this->ticket->subject}")
            ->greeting("Hello {$notifiable->name},")
            ->line("{$this->ticket->client?->name} {$verb}:")
            ->line("Ticket: {$this->ticket->ticket_number} — {$this->ticket->subject} (priority: {$this->ticket->priority})")
            ->line('Open MoBilling → Support Tickets to respond.');
    }
}
