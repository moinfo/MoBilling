<?php

namespace App\Console\Commands;

use App\Models\CronLog;
use App\Models\Statutory;
use Illuminate\Console\Command;

class GenerateRecurringBills extends Command
{
    protected $signature = 'bills:generate-recurring';
    protected $description = 'Generate bills for active statutory obligations due today or overdue with no unpaid bill';

    public function handle(): int
    {
        $startedAt = now();

        try {
            $statutories = Statutory::where('is_active', true)
                ->where('next_due_date', '<=', now()->toDateString())
                ->whereDoesntHave('currentBill')
                ->get();

            $count = 0;
            foreach ($statutories as $statutory) {
                $statutory->generateBill();
                $this->info("Generated bill for: {$statutory->name}");
                $count++;
            }

            $this->info("Done. Generated {$count} bill(s).");

            CronLog::create([
                'tenant_id' => null,
                'command' => $this->signature,
                'description' => "Generated {$count} statutory bill(s)",
                'results' => ['bills_generated' => $count],
                'status' => 'success',
                'started_at' => $startedAt,
                'finished_at' => now(),
            ]);

            return Command::SUCCESS;
        } catch (\Throwable $e) {
            CronLog::create([
                'tenant_id' => null,
                'command' => $this->signature,
                'description' => 'Failed to generate recurring bills',
                'status' => 'failed',
                'error' => $e->getMessage(),
                'started_at' => $startedAt,
                'finished_at' => now(),
            ]);

            $this->error($e->getMessage());
            return Command::FAILURE;
        }
    }
}
