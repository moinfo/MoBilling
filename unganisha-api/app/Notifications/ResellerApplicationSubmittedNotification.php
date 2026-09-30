<?php

namespace App\Notifications;

use App\Models\ResellerApplication;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Notification;

/** A client applied to become a white-label reseller — staff with reseller_applications.manage get pinged. */
class ResellerApplicationSubmittedNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(public ResellerApplication $application) {}

    public function via($notifiable): array
    {
        return ['database', \App\Channels\FcmChannel::class];
    }

    public function toFcm($notifiable): ?array
    {
        return [
            'title' => 'New reseller application',
            'body'  => "{$this->application->brand_name} ({$this->application->requested_domain}) applied to become a white-label reseller",
            'data'  => ['type' => 'reseller_application_submitted', 'application_id' => $this->application->id],
        ];
    }

    public function toArray($notifiable): array
    {
        return [
            'type'           => 'reseller_application_submitted',
            'title'          => 'New reseller application',
            'message'        => "{$this->application->brand_name} ({$this->application->requested_domain}) applied to become a white-label reseller",
            'application_id' => $this->application->id,
            'url'            => '/reseller-applications',
        ];
    }
}
