<?php

namespace App\Console\Commands;

use App\Models\Client;
use App\Models\Domain;
use App\Services\Registrar\ClientRegistryContact;
use App\Services\Registrar\DomainRegistrarManager;
use App\Services\Registrar\FredHttpDriver;
use App\Services\Registrar\NameComDomainService;
use Illuminate\Console\Command;

/**
 * One-time backfill for the 2026-11-26 .tz registry compliance notice:
 * every domain registered before ClientRegistryContact existed got the
 * platform's own contact (CONTACT-MOINFOTECH) as registrant AND admin.
 * This re-points each affected domain at a real per-client contact instead
 * — same resolve-or-create logic RegisterDomainJob now uses going forward.
 *
 * Safe to re-run: a fixed domain's local registrant_handle no longer
 * matches the stale-contact filter below, so it's skipped on later runs.
 * Defaults to a dry run — nothing is mutated without --execute.
 */
class FixSharedRegistrantContacts extends Command
{
    private const STALE_CONTACT = 'CONTACT-MOINFOTECH';

    protected $signature = 'domains:fix-shared-registrant
        {--execute : Actually create contacts and update domains (default is a dry run)}
        {--limit=0 : Stop after this many domains (0 = no limit)}';

    protected $description = 'Re-point domains still on CONTACT-MOINFOTECH at a real per-client registry contact';

    public function handle(DomainRegistrarManager $registrar): int
    {
        $execute = (bool) $this->option('execute');
        $limit = (int) $this->option('limit');

        $domains = Domain::withoutGlobalScopes()
            ->with('client')
            ->where('registrant_handle', self::STALE_CONTACT)
            ->whereNotIn('status', ['cancelled', 'transferred_out'])
            ->whereNotNull('client_id')
            ->orderBy('name')
            ->get()
            ->reject(fn (Domain $d) => NameComDomainService::isNameComDomain($d) || !str_ends_with($d->name, '.tz'))
            ->values();

        if ($limit > 0) {
            $domains = $domains->take($limit);
        }

        $this->info(($execute ? 'EXECUTING' : 'DRY RUN') . " — {$domains->count()} domain(s) to consider.");

        $fixed = 0;
        $skippedNoEmail = [];
        $failed = [];

        foreach ($domains as $domain) {
            /** @var Client|null $client */
            $client = $domain->client;

            if (!$client || !$client->email) {
                $skippedNoEmail[] = $domain->name . ' (client: ' . ($client?->name ?? 'none') . ')';
                continue;
            }

            try {
                $driver = $registrar->driverFor($domain->tenant_id, $domain->id);
                if (!$driver instanceof FredHttpDriver) {
                    continue; // only the .tz/FRED driver has this concept
                }

                if (!$execute) {
                    $willCreate = $client->registry_contact_id ? 'reuse ' . $client->registry_contact_id : 'create new contact';
                    $this->line("  {$domain->name} -> {$client->name} <{$client->email}> ({$willCreate})");
                    $fixed++;
                    continue;
                }

                $contactId = ClientRegistryContact::resolve($driver, $client);
                if (!$contactId) {
                    $skippedNoEmail[] = $domain->name . ' (contact creation failed for ' . $client->name . ')';
                    continue;
                }

                $driver->updateDomain($domain->name, [
                    'registrant_id' => $contactId,
                    'add_admins'    => [$contactId],
                    'rem_admins'    => [self::STALE_CONTACT],
                ]);

                $domain->update([
                    'registrant_handle' => $contactId,
                    'admin_handle'      => $contactId,
                ]);

                $this->line("  ✓ {$domain->name} -> {$contactId} ({$client->name})");
                $fixed++;

                usleep(300_000); // pace EPP calls — this is a real, no-rush backfill
            } catch (\Throwable $e) {
                $failed[] = "{$domain->name}: {$e->getMessage()}";
                $this->error("  ✗ {$domain->name}: {$e->getMessage()}");
            }
        }

        $this->newLine();
        $this->info(($execute ? 'Fixed' : 'Would fix') . ": {$fixed}");
        if ($skippedNoEmail) {
            $this->warn('Skipped (no usable client email — needs manual contact info): ' . count($skippedNoEmail));
            foreach ($skippedNoEmail as $s) {
                $this->line("  - {$s}");
            }
        }
        if ($failed) {
            $this->error('Failed: ' . count($failed));
            foreach ($failed as $f) {
                $this->line("  - {$f}");
            }
        }

        return self::SUCCESS;
    }
}
