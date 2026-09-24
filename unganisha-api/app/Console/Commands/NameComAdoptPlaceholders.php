<?php

namespace App\Console\Commands;

use App\Services\Registrar\NameComPricingService;
use Illuminate\Console\Command;

/** Offline, idempotent: unmanaged placeholder TLD rows (registrar fred + is_unmanaged) become Name.com rows, off sale. No network. */
class NameComAdoptPlaceholders extends Command
{
    protected $signature = 'namecom:adopt-placeholders {tenant : tenant id} {--tlds=com,net,org : comma list of TLDs, or "all"} {--apply : write changes (default is a dry-run report)}';
    protected $description = 'Adopt unmanaged placeholder TLD rows (e.g. com/net/org) as Name.com rows. Dry-run unless --apply.';

    public function handle(NameComPricingService $svc): int
    {
        $only = $this->option('tlds') === 'all' ? null : array_map('trim', explode(',', strtolower($this->option('tlds'))));
        $apply = (bool) $this->option('apply');
        $rep = $svc->adoptPlaceholders($this->argument('tenant'), $apply, $only);
        foreach ($rep as $r) $this->line(".{$r['tld']}  {$r['id']}  {$r['action']}");
        $this->info(($apply ? 'APPLIED' : 'DRY-RUN (nothing written)') . ': ' . count($rep) . ' row(s).');
        return self::SUCCESS;
    }
}
