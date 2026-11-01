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
        $winnerName = $this->cycle->winner?->name ?? 'Hakuna mshindi';

        return [
            'title' => 'Mfanyakazi Bora wa Mwezi',
            'body'  => "{$winnerName} amechaguliwa Mfanyakazi Bora wa mwezi {$this->cycle->period_month_key} kwa kura {$this->cycle->winner_vote_count}.",
            'data'  => ['type' => 'eotm_winner', 'cycle_id' => $this->cycle->id],
        ];
    }

    public function toArray($notifiable): array
    {
        $winnerName = $this->cycle->winner?->name ?? 'Hakuna mshindi';

        return [
            'type' => 'eotm_winner',
            'title' => 'Mfanyakazi Bora wa Mwezi',
            'message' => "{$winnerName} amechaguliwa Mfanyakazi Bora wa mwezi {$this->cycle->period_month_key} kwa kura {$this->cycle->winner_vote_count}.",
            'cycle_id' => $this->cycle->id,
            'url' => '/dashboard',
        ];
    }
}
