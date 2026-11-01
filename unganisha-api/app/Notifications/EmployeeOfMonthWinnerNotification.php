<?php

namespace App\Notifications;

use App\Models\EmployeeOfMonthCycle;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Notification;

class EmployeeOfMonthWinnerNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(public EmployeeOfMonthCycle $cycle) {}

    public function via($notifiable): array
    {
        return ['database', \App\Channels\FcmChannel::class];
    }

    public function toFcm($notifiable): ?array
    {
        $winnerName = $this->cycle->winner?->name ?? 'No winner';

        return [
            'title' => 'Employee of the Month',
            'body'  => "{$winnerName} was voted Employee of the Month for {$this->cycle->period_month_key} with {$this->cycle->winner_vote_count} vote(s).",
            'data'  => ['type' => 'eotm_winner', 'cycle_id' => $this->cycle->id],
        ];
    }

    public function toArray($notifiable): array
    {
        $winnerName = $this->cycle->winner?->name ?? 'No winner';

        return [
            'type' => 'eotm_winner',
            'title' => 'Employee of the Month',
            'message' => "{$winnerName} was voted Employee of the Month for {$this->cycle->period_month_key} with {$this->cycle->winner_vote_count} vote(s).",
            'cycle_id' => $this->cycle->id,
            'url' => '/dashboard',
        ];
    }
}
