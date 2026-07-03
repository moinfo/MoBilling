<?php

namespace App\Console\Commands;

use App\Models\Tenant;
use App\Services\WhmcsImport\WhmcsImporter;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

class WhmcsImport extends Command
{
    protected $signature = 'whmcs:import
        {--tenant= : Target tenant UUID (required)}
        {--stage=all : all|products|clients|users|services|invoices|payments|domains}
        {--dry-run : Run inside a transaction and roll back}
        {--limit= : Limit rows per source table (testing)}';

    protected $description = 'One-time WHMCS -> MoBilling data import (docs/IMPLEMENTATION_PLAN.md §C1)';

    private const STAGES = ['products', 'clients', 'users', 'services', 'invoices', 'payments', 'domains'];

    public function handle(): int
    {
        $tenant = Tenant::find($this->option('tenant'));
        if (!$tenant) {
            $this->error('Pass --tenant=<uuid>. Available tenants:');
            Tenant::all(['id', 'name'])->each(fn ($t) => $this->line("  {$t->id}  {$t->name}"));
            return self::FAILURE;
        }

        $stage  = $this->option('stage');
        $stages = $stage === 'all' ? self::STAGES : [$stage];
        if (array_diff($stages, self::STAGES)) {
            $this->error('Unknown stage. Use: all|' . implode('|', self::STAGES));
            return self::FAILURE;
        }

        $dry      = (bool) $this->option('dry-run');
        $importer = new WhmcsImporter($tenant->id, $this->option('limit') ? (int) $this->option('limit') : null);

        $this->info(sprintf('WHMCS import -> tenant "%s" (%s)%s', $tenant->name, $tenant->id, $dry ? ' [DRY RUN]' : ''));

        DB::beginTransaction();
        try {
            foreach ($stages as $s) {
                $this->line("Stage: {$s} ...");
                $importer->{'import' . ucfirst($s)}();
            }
        } catch (\Throwable $e) {
            DB::rollBack();
            $this->error("FAILED in stage — rolled back: {$e->getMessage()}");
            $this->line($e->getFile() . ':' . $e->getLine());
            return self::FAILURE;
        }

        $dry ? DB::rollBack() : DB::commit();

        // Report
        $rows = [];
        foreach ($importer->report as $s => $r) {
            $rows[] = [$s, $r['imported'] ?? 0, count($r['skipped'] ?? [])];
        }
        $this->table(['stage', 'imported', 'skipped'], $rows);

        foreach ($importer->report as $s => $r) {
            foreach (array_slice($r['skipped'] ?? [], 0, 15) as [$reason, $ref]) {
                $this->line("  [{$s}] {$reason}: {$ref}");
            }
            if (count($r['skipped'] ?? []) > 15) {
                $this->line('  [' . $s . '] ... and ' . (count($r['skipped']) - 15) . ' more (see report file)');
            }
        }

        $file = 'whmcs-import-report-' . now()->format('Ymd-His') . ($dry ? '-dry' : '') . '.json';
        Storage::put($file, json_encode($importer->report, JSON_PRETTY_PRINT));
        $this->info("Full report: storage/app/{$file}");
        $this->info($dry ? 'DRY RUN — all changes rolled back.' : 'Import committed.');

        return self::SUCCESS;
    }
}
