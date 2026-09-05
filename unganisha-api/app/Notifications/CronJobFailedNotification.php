<?php

namespace App\Notifications;

use App\Models\CronLog;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * A scheduled command threw and its `CronLog` row was written with
 * `status: 'failed'`. These commands run tenant-wide in one pass (their
 * `CronLog.tenant_id` is null), so a failure is a platform problem, not one
 * tenant's — fired to platform super admins, not tenant staff. Before this,
 * the only way to notice was opening Automation > Cron Logs and spotting a
 * red row.
 */
class CronJobFailedNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(public CronLog $cronLog) {}

    public function via($notifiable): array
    {
        return ['database', 'mail', \App\Channels\FcmChannel::class];
    }

    public function toFcm($notifiable): ?array
    {
        return [
            'title' => 'Scheduled job failed',
            'body'  => "{$this->cronLog->command}: " . ($this->cronLog->error ?? $this->cronLog->description ?? 'no details'),
            'data'  => ['type' => 'cron_failure', 'cron_log_id' => $this->cronLog->id],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        return (new MailMessage)
            ->subject("Scheduled job failed: {$this->cronLog->command}")
            ->line("{$this->cronLog->command} failed at {$this->cronLog->finished_at?->format('d M Y H:i')}.")
            ->line('Error: ' . ($this->cronLog->error ?? $this->cronLog->description ?? 'no details recorded'));
    }

    public function toArray($notifiable): array
    {
        return [
            'type'    => 'cron_failure',
            'title'   => 'Scheduled job failed',
            'message' => "{$this->cronLog->command}: " . ($this->cronLog->error ?? $this->cronLog->description ?? 'no details'),
            'cron_log_id' => $this->cronLog->id,
            'url'     => '/admin',
        ];
    }
}
