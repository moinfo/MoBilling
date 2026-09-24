<?php

namespace App\Notifications;

use App\Models\Domain;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;

/** STAFF ONLY: a paid Name.com domain order is waiting in the registration queue. */
class NameComRegistrationPendingNotification extends Notification
{
    use Queueable;

    public function __construct(public Domain $domain, public ?string $autoFailure = null) {}

    public function via($notifiable): array
    {
        return ['database', \App\Channels\FcmChannel::class];
    }

    private function text(): string
    {
        return $this->autoFailure
            ? "{$this->domain->name} - automatic registration did not run ({$this->autoFailure}). Register it at Name.com from Domains."
            : "{$this->domain->name} - paid, waiting for you to register it at Name.com (Domains > Register at Name.com).";
    }

    public function toFcm($notifiable): ?array
    {
        return ['title' => 'Name.com domain waiting for registration', 'body' => $this->text(),
            'data' => ['type' => 'namecom_registration_pending', 'domain_id' => $this->domain->id]];
    }

    public function toArray($notifiable): array
    {
        return ['type' => 'namecom_registration_pending', 'title' => 'Name.com domain waiting for registration',
            'message' => $this->text(), 'domain_id' => $this->domain->id, 'url' => '/domains'];
    }
}
