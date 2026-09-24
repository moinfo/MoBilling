<?php

namespace App\Notifications;

use Illuminate\Notifications\Notification;

/** Staff-only: a Name.com API account was rejected during the bulk refresh and is now skipped until its token is fixed. */
class NameComAccountInvalidNotification extends Notification
{
    public function __construct(public string $accountLabel, public string $reason) {}

    public function via($notifiable): array
    {
        return ['database'];
    }

    public function toArray($notifiable): array
    {
        return [
            'type'    => 'namecom_account_invalid',
            'title'   => 'Name.com account needs attention',
            'message' => "The Name.com account \"{$this->accountLabel}\" was rejected ({$this->reason}). Its domains are skipped until you update the token under Domains > Name.com.",
            'url'     => '/domains',
        ];
    }
}
