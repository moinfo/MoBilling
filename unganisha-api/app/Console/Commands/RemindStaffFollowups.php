<?php

namespace App\Console\Commands;

use App\Models\CronLog;
use App\Models\Followup;
use App\Notifications\FollowupReminderDigestNotification;
use Carbon\Carbon;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class RemindStaffFollowups extends Command
{
    protected $signature = 'followups:remind-staff';

    protected $description = 'Send each staff member one daily digest of their follow-up calls due today and overdue.';

    public function handle(): int
    {
        $startedAt = now();
        $today = Carbon::today();

        try {
            $rows = Followup::withoutGlobalScopes()
                ->whereNotNull('user_id')
                ->whereIn('status', ['pending', 'open', 'broken'])
                ->whereDate('next_followup', '<=', $today)
                ->whereHas('document', fn ($q) => $q->where('status', '!=', 'cancelled'))
                ->with(['client', 'document', 'user.tenant'])
                ->orderBy('next_followup')
                ->get();

            $sent = 0;
            foreach ($rows->groupBy('user_id') as $userId => $userRows) {
                $user = $userRows->first()->user;
                if (!$user || !$user->tenant) {
                    continue;
                }

                // Idempotent: at most one digest per staff member per day, even if the command reruns.
                $already = DB::table('notifications')
                    ->where('notifiable_type', get_class($user))
                    ->where('notifiable_id', $userId)
                    ->where('type', FollowupReminderDigestNotification::class)
                    ->whereDate('created_at', $today)
                    ->exists();
                if ($already) {
                    continue;
                }

                $dueToday = $userRows->filter(fn ($f) => $f->next_followup && $f->next_followup->isSameDay($today));
                $overdue = $userRows->filter(fn ($f) => $f->next_followup && $f->next_followup->lt($today));
                if ($dueToday->isEmpty() && $overdue->isEmpty()) {
                    continue;
                }

                $items = $overdue->concat($dueToday)->take(5)->map(fn ($f) => [
                    'client' => $f->client?->name ?? '-',
                    'invoice' => $f->document?->document_number ?? '-',
                    'due' => $f->next_followup?->toDateString(),
                ])->values()->all();

                $user->notify(new FollowupReminderDigestNotification($user->tenant, $items, $dueToday->count(), $overdue->count()));
                $sent++;
            }

            $this->info("Sent {$sent} staff reminder digest(s).");

            CronLog::create([
                'tenant_id' => null,
                'command' => $this->signature,
                'description' => "Sent {$sent} staff follow-up reminder digest(s)",
                'results' => ['digests_sent' => $sent],
                'status' => 'success',
                'started_at' => $startedAt,
                'finished_at' => now(),
            ]);

            return self::SUCCESS;
        } catch (\Throwable $e) {
            CronLog::create([
                'tenant_id' => null,
                'command' => $this->signature,
                'description' => 'Failed to send staff follow-up reminders',
                'status' => 'failed',
                'error' => $e->getMessage(),
                'started_at' => $startedAt,
                'finished_at' => now(),
            ]);

            $this->error($e->getMessage());

            return self::FAILURE;
        }
    }
}
