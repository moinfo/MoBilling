<?php

namespace App\Console\Commands;

use App\Models\Bill;
use App\Models\CronLog;
use App\Models\Tenant;
use App\Models\User;
use App\Notifications\BillDueReminderNotification;
use App\Notifications\BillOverdueNotification;
use Illuminate\Console\Command;

class SendBillReminders extends Command
{
    protected $signature = 'bills:send-reminders';
    protected $description = 'Send reminders for upcoming and overdue bills';

    public function handle(): void
    {
        $startedAt = now();

        try {
            // Upcoming bills (within reminder window)
            $upcomingBills = Bill::withoutGlobalScopes()
                ->where('is_active', true)
                ->whereRaw('DATE_SUB(due_date, INTERVAL remind_days_before DAY) <= CURDATE()')
                ->where('due_date', '>=', now()->toDateString())
                ->get();

            foreach ($upcomingBills as $bill) {
                $tenant = Tenant::find($bill->tenant_id);
                if (!$tenant) continue;

                $users = User::where('tenant_id', $bill->tenant_id)->get();
                foreach ($users as $user) {
                    $user->notify(new BillDueReminderNotification($bill, $tenant));
                }
            }

            // Overdue bills
            $overdueBills = Bill::withoutGlobalScopes()
                ->where('is_active', true)
                ->where('due_date', '<', now()->toDateString())
                ->get();

            foreach ($overdueBills as $bill) {
                $tenant = Tenant::find($bill->tenant_id);
                if (!$tenant) continue;

                $users = User::where('tenant_id', $bill->tenant_id)->get();
                foreach ($users as $user) {
                    $user->notify(new BillOverdueNotification($bill, $tenant));
                }
            }

            $upcomingCount = $upcomingBills->count();
            $overdueCount = $overdueBills->count();

            $this->info("Sent reminders for {$upcomingCount} upcoming and {$overdueCount} overdue bills.");

            CronLog::create([
                'tenant_id' => null,
                'command' => $this->signature,
                'description' => "Sent reminders: {$upcomingCount} upcoming, {$overdueCount} overdue",
                'results' => ['upcoming_reminders' => $upcomingCount, 'overdue_reminders' => $overdueCount],
                'status' => 'success',
                'started_at' => $startedAt,
                'finished_at' => now(),
            ]);
        } catch (\Throwable $e) {
            CronLog::create([
                'tenant_id' => null,
                'command' => $this->signature,
                'description' => 'Failed to send bill reminders',
                'status' => 'failed',
                'error' => $e->getMessage(),
                'started_at' => $startedAt,
                'finished_at' => now(),
            ]);

            $this->error($e->getMessage());
        }
    }
}
