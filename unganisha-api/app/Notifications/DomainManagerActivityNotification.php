<?php

namespace App\Notifications;

use App\Models\Domain;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/** Staff alert: a sensitive Domain Manager change (contacts, glue hosts, forwarding). Never carries personal data. */
class DomainManagerActivityNotification extends Notification
{
    use Queueable;

    public function __construct(public Domain $domain, public string $what, public bool $byClient) {}

    public function via($notifiable): array
    {
        $ch = ['database', \App\Channels\FcmChannel::class];
        if ($notifiable->email) $ch[] = 'mail';
        return $ch;
    }

    private function title(): string
    {
        return match ($this->what) {
            'contacts'      => 'Domain contact details changed',
            'host'          => 'Custom nameserver host changed',
            'url_forward'   => 'Website forwarding changed',
            'email_forward' => 'Email forwarding changed',
            default         => 'Domain settings changed',
        };
    }

    private function text(): string
    {
        $who = $this->byClient ? 'The client' : 'A staff member';
        return "{$who} changed: " . strtolower($this->title()) . " for {$this->domain->name}. Forwarding may point to an external address.";
    }

    public function toFcm($notifiable): ?array
    {
        return ['title' => $this->title(), 'body' => $this->text(), 'data' => ['type' => 'domain_manager', 'domain_id' => $this->domain->id]];
    }

    public function toArray($notifiable): array
    {
        return ['type' => 'domain_manager', 'title' => $this->title(), 'message' => $this->text(), 'domain_id' => $this->domain->id, 'url' => '/domains/' . $this->domain->id];
    }

    public function toMail($notifiable): MailMessage
    {
        return (new MailMessage)->subject($this->title() . ' - ' . $this->domain->name)->line($this->text())
            ->line('If this was unexpected, contact the client and review the domain.')
            ->action('View domain', url('/domains/' . $this->domain->id));
    }
}
