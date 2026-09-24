<?php

namespace App\Notifications;

use App\Channels\FcmChannel;
use App\Models\LinodeDomainRequest;
use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * event: requested (to staff, in-app) | approved | rejected (to the client, email + push).
 * No SMS / WhatsApp on purpose.
 */
class LinodeDomainRequestNotification extends Notification
{
    use Queueable, HasTenantBranding;

    public function __construct(public LinodeDomainRequest $request, public string $event, public ?Tenant $tenant = null, public ?string $serverName = null) {}

    public function via($notifiable): array
    {
        if ($this->event === 'requested') {
            return ['database', FcmChannel::class];
        }
        $channels = [];
        if ($this->tenant?->email_enabled && $notifiable->email) $channels[] = 'mail';
        $channels[] = FcmChannel::class;
        return $channels;
    }

    private function title(): string
    {
        return match ($this->event) {
            'requested' => 'Domain request for a Linode server',
            'approved' => "Domain {$this->request->domain} added",
            default => "Domain {$this->request->domain} not added",
        };
    }

    private function text(): string
    {
        $d = $this->request->domain;
        return match ($this->event) {
            'requested' => "{$this->request->client?->name} asked to add {$d} to server {$this->serverName}.",
            'approved' => "Your domain {$d} was added to your server {$this->serverName}. Set the nameservers at your registrar to ns1.linode.com - ns5.linode.com so it takes effect.",
            default => "Your request to add {$d} to server {$this->serverName} was declined." . ($this->request->note ? " Reason: {$this->request->note}" : ''),
        };
    }

    public function toFcm($notifiable): ?array
    {
        return ['title' => $this->title(), 'body' => $this->text(), 'data' => ['type' => 'linode_domain_request', 'request_id' => $this->request->id]];
    }

    public function toArray($notifiable): array
    {
        return ['type' => 'linode_domain_request', 'title' => $this->title(), 'message' => $this->text(), 'url' => '/linode', 'request_id' => $this->request->id];
    }

    public function toMail($notifiable): MailMessage
    {
        $mail = (new MailMessage)->subject($this->title())->greeting('Hello ' . ($notifiable->name ?? '') . ',')->line($this->text());
        return $this->tenant ? $this->applyBranding($mail, $this->tenant) : $mail;
    }
}
