<?php

namespace App\Console\Commands;

use App\Models\Statutory;
use Illuminate\Console\Command;

class GenerateRecurringBills extends Command
{
    protected $signature = 'bills:generate-recurring';
    protected $description = 'Generate bills for active statutory obligations due today or overdue with no unpaid bill';

    public function handle(): int
    {
        $statutories = Statutory::where('is_active', true)
            ->where('next_due_date', '<=', now()->toDateString())
            ->whereDoesntHave('currentBill') // no unpaid bill exists
            ->get();

        $count = 0;
        foreach ($statutories as $statutory) {
            $statutory->generateBill();
            $this->info("Generated bill for: {$statutory->name}");
            $count++;
        }

        $this->info("Done. Generated {$count} bill(s).");
        return Command::SUCCESS;
    }
}
