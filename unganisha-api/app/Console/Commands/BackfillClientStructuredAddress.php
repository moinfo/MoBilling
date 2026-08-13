<?php

namespace App\Console\Commands;

use App\Models\Client;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * One-time backfill: WHMCS-imported clients (legacy_id set) already have
 * structured first/last/company name and address1-2/city/state/postcode/
 * country in the source WHMCS database (WhmcsImporter::importClients()
 * flattens them into `name`/`address` on import) — pull the untouched
 * originals straight from tblclients instead of trying to re-parse the
 * flattened strings. Only fills currently-empty structured columns, so
 * it's safe to re-run and never overwrites anything staff enter by hand.
 */
class BackfillClientStructuredAddress extends Command
{
    protected $signature = 'clients:backfill-structured-address {--tenant=} {--dry-run}';
    protected $description = 'Backfill first/last/company name and structured address for WHMCS-imported clients';

    public function handle(): int
    {
        $dry = (bool) $this->option('dry-run');

        $query = Client::withoutGlobalScopes()
            ->whereNotNull('legacy_id')
            ->whereNull('first_name'); // idempotent: only ever fills empty rows

        if ($tenant = $this->option('tenant')) {
            $query->where('tenant_id', $tenant);
        }

        $clients = $query->get(['id', 'tenant_id', 'legacy_id', 'name', 'address']);

        if ($clients->isEmpty()) {
            $this->info('Nothing to backfill.');
            return self::SUCCESS;
        }

        $whmcsRows = DB::connection('whmcs')->table('tblclients')
            ->whereIn('id', $clients->pluck('legacy_id'))
            ->get()->keyBy('id');

        $updated = 0;
        $missing = 0;

        foreach ($clients as $client) {
            $w = $whmcsRows->get($client->legacy_id);
            if (!$w) {
                $missing++;
                continue;
            }

            $data = [
                'first_name'   => trim((string) $w->firstname) ?: null,
                'last_name'    => trim((string) $w->lastname) ?: null,
                'company_name' => trim((string) $w->companyname) ?: null,
                'address_1'    => trim((string) $w->address1) ?: null,
                'address_2'    => trim((string) $w->address2) ?: null,
                'city'         => trim((string) $w->city) ?: null,
                'state'        => trim((string) $w->state) ?: null,
                'postcode'     => trim((string) $w->postcode) ?: null,
                'country'      => $w->country ? strtoupper(substr(trim($w->country), 0, 2)) : null,
            ];

            if ($dry) {
                $this->line("[dry] {$client->name} (legacy #{$client->legacy_id}): " . json_encode(array_filter($data)));
            } else {
                $client->update($data);
            }
            $updated++;
        }

        $this->info(($dry ? 'Dry run: ' : '') . "{$updated} client(s) backfilled, {$missing} legacy_id not found in WHMCS.");

        return self::SUCCESS;
    }
}
