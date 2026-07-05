<?php

namespace App\Console\Commands;

use App\Models\CronLog;
use App\Models\Domain;
use App\Models\DomainRegistryEvent;
use App\Models\RegistrarAccount;
use App\Services\Registrar\FredHttpDriver;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;

/**
 * Drain the FRED registry poll queue.
 *
 * SAFE DEFAULT: with no flag it only PEEKS the oldest message (no dequeue),
 * so you can inspect the live queue. `--drain` stores each message, ACKs it
 * (irreversible — removes it from the registry queue), and reacts to the
 * important ones (transfer-away / pending-delete flag the domain).
 */
class PollRegistry extends Command
{
    protected $signature = 'registry:poll {--drain : Dequeue (ack) and process messages — irreversible} {--limit=100 : Max messages to drain in one run}';
    protected $description = 'Read/drain the FRED registry poll message queue (transfers away, deletions, expiry, low credit)';

    public function handle(): int
    {
        $account = RegistrarAccount::whereNull('tenant_id')->where('is_active', true)->first();
        if (!$account) {
            $this->error('No active platform registrar account.');
            return self::FAILURE;
        }

        $driver = new FredHttpDriver($account);
        $drain  = (bool) $this->option('drain');
        $limit  = (int) $this->option('limit');
        $startedAt = now();
        $stored = 0; $acked = 0; $acted = 0;

        // Peek mode: read the oldest once and show it (no state change).
        if (!$drain) {
            try {
                $res = $driver->pollRequest();
            } catch (\Throwable $e) {
                $this->error('Poll failed: ' . $e->getMessage());
                return self::FAILURE;
            }
            $count = $res['count'] ?? 0;
            $this->info("Queue depth: {$count} message(s).");
            if (($msg = $res['message'] ?? null)) {
                $this->line("Oldest: [{$msg['id']}] {$msg['type']} — " . ($msg['text'] ?? ''));
                $this->comment('Peek only — nothing dequeued. Run with --drain to process & ack.');
            }
            return self::SUCCESS;
        }

        // Drain mode: read → store → ack → act, until empty or limit.
        for ($i = 0; $i < $limit; $i++) {
            try {
                $res = $driver->pollRequest();
            } catch (\Throwable $e) {
                $this->warn('Poll read failed: ' . $e->getMessage());
                break;
            }
            $msg = $res['message'] ?? null;
            if (!$msg) {
                break; // queue empty
            }

            $event = $this->store($account, $msg);
            $stored++;
            $this->act($event);
            if ($event->acted) {
                $acted++;
            }

            try {
                $driver->pollAck((string) $msg['id']);
                $event->update(['acked' => true]);
                $acked++;
            } catch (\Throwable $e) {
                $this->warn("Ack failed for {$msg['id']}: {$e->getMessage()} — stopping to avoid a loop.");
                break; // if ack fails, the next read returns the same message → stop
            }
        }

        $this->info("Drained: stored {$stored}, acked {$acked}, acted {$acted}.");

        CronLog::create([
            'tenant_id'   => null,
            'command'     => $this->signature,
            'description' => "Registry poll drained {$stored} message(s) ({$acted} actioned)",
            'results'     => compact('stored', 'acked', 'acted'),
            'status'      => 'success',
            'started_at'  => $startedAt,
            'finished_at' => now(),
        ]);

        return self::SUCCESS;
    }

    private function store(RegistrarAccount $account, array $msg): DomainRegistryEvent
    {
        $domain = $this->domainFrom($msg);

        return DomainRegistryEvent::updateOrCreate(
            ['registry_msg_id' => $msg['id']],
            [
                'tenant_id' => $account->tenant_id,
                'msg_type'  => $msg['type'] ?? null,
                'msg_date'  => !empty($msg['date']) ? \Carbon\Carbon::parse($msg['date']) : null,
                'domain'    => $domain,
                'text'      => $msg['text'] ?? null,
                'data'      => $msg['data'] ?? null,
            ]
        );
    }

    /** React to the actionable message types. */
    private function act(DomainRegistryEvent $event): void
    {
        $type = strtolower((string) $event->msg_type);
        if (!$event->domain) {
            return;
        }

        $domain = Domain::withoutGlobalScopes()->where('name', $event->domain)->first();
        if (!$domain) {
            return;
        }

        // Transfer away / deletion at the registry → reflect it locally + log.
        $isTransfer = str_contains($type, 'transfer');
        $isDeletion = str_contains($type, 'del');   // DelData / IdleObjectDeletion / DomainDeletion

        if ($isTransfer || $isDeletion) {
            $domain->update([
                'status' => $isDeletion ? 'cancelled' : 'transferred_out',
                'meta'   => array_merge($domain->meta ?? [], [
                    'registry_event'    => $event->msg_type,
                    'registry_event_at' => now()->toIso8601String(),
                ]),
            ]);
            \App\Models\DomainLog::create([
                'tenant_id' => $domain->tenant_id,
                'domain_id' => $domain->id,
                'action'    => 'registry_' . ($isDeletion ? 'deletion' : 'transfer_away'),
                'request'   => ['msg_id' => $event->registry_msg_id, 'type' => $event->msg_type],
                'status'    => 'success',
            ]);
            $event->update(['acted' => true]);
            Log::warning("Registry event on {$domain->name}: {$event->msg_type}");
        }
    }

    /** Best-effort domain-name extraction from the message payload. */
    private function domainFrom(array $msg): ?string
    {
        foreach (['name', 'handle', 'domain', 'obj_id', 'id'] as $k) {
            $v = $msg['data'][$k] ?? null;
            if ($v && str_contains((string) $v, '.')) {
                return strtolower(trim((string) $v));
            }
        }
        // fall back to a domain-looking token in the text
        if (preg_match('/([a-z0-9-]+\.[a-z.]{2,})/i', (string) ($msg['text'] ?? ''), $m)) {
            return strtolower($m[1]);
        }
        return null;
    }
}
