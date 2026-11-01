<?php

namespace App\Notifications;

use App\Models\EmployeeOfMonthCycle;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Notification;

class EmployeeOfMonthVotingOpenNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(public EmployeeOfMonthCycle $cycle) {}

    public function via($notifiable): array
    {
        return ['database', \App\Channels\FcmChannel::class];
    }

    public function toFcm($notifiable): ?array
    {
        return [
            'title' => 'Employee of the Month — vote now',
            'body'  => "Piga kura mfanyakazi bora wa mwezi uliopita kabla ya {$this->cycle->voting_closes_on->format('d M')}.",
            'data'  => ['type' => 'eotm_vote_open', 'cycle_id' => $this->cycle->id],
        ];
    }

    public function toArray($notifiable): array
    {
        return [
            'type' => 'eotm_vote_open',
            'title' => 'Employee of the Month — vote now',
            'message' => "Piga kura mfanyakazi bora wa mwezi uliopita kabla ya {$this->cycle->voting_closes_on->format('d M')}.",
            'cycle_id' => $this->cycle->id,
            'url' => '/dashboard',
        ];
    }
}
