<?php

namespace App\Notifications;

use App\Models\Domain;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/** Staff alert: a domain was unlocked or its transfer code requested. Never carries the code. */
class DomainTransferActivityNotification extends Notification
{
    use Queueable;

    public function __construct(public Domain $domain, public string $event, public bool $byClient) {}

    public function via($notifiable): array
    {
        $ch = ['database', \App\Channels\FcmChannel::class];
        if ($notifiable->email) $ch[] = 'mail';
        return $ch;
    }

    private function title(): string
    {
        return $this->event === 'unlocked' ? 'Domain unlocked for transfer' : 'Transfer code requested';
    }

    private function text(): string
    {
        $who = $this->byClient ? 'The client' : 'A staff member';
        return $this->event === 'unlocked'
            ? "{$who} unlocked {$this->domain->name}. It can now be transferred to another registrar."
            : "{$who} requested the transfer authorization code for {$this->domain->name}.";
    }

    public function toFcm($notifiable): ?array
    {
        return ['title' => $this->title(), 'body' => $this->text(), 'data' => ['type' => 'domain_transfer', 'domain_id' => $this->domain->id]];
    }

    public function toArray($notifiable): array
    {
        return ['type' => 'domain_transfer', 'title' => $this->title(), 'message' => $this->text(), 'domain_id' => $this->domain->id, 'url' => '/domains/' . $this->domain->id];
    }

    public function toMail($notifiable): MailMessage
    {
        return (new MailMessage)->subject($this->title() . ' - ' . $this->domain->name)->line($this->text())
            ->line('If this was unexpected, contact the client and review the domain.')
            ->action('View domain', url('/domains/' . $this->domain->id));
    }
}
