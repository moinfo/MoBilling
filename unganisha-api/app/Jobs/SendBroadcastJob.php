<?php

namespace App\Jobs;

use App\Models\Broadcast;
use App\Models\Client;
use App\Models\Tenant;
use App\Notifications\BroadcastNotification;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Support\Facades\Log;

/**
 * Does the actual per-recipient sending for a Broadcast. Runs on a real
 * queue worker (systemd unit mobilling-queue.service, `queue:work
 * --queue=broadcasts`) rather than this app's default QUEUE_CONNECTION=sync
 * — dispatched explicitly onto the 'database' connection/'broadcasts' queue
 * (BroadcastController), so every other job in this app still runs inline
 * on 'sync' exactly as before; only broadcasts are routed to the worker.
 *
 * Previously ran inline via ->afterResponse() in the same php-fpm worker
 * that handled the request — that silently died partway through any
 * broadcast bigger than ~25 WhatsApp recipients, because
 * fastcgi_finish_request() does NOT reset PHP's own max_execution_time
 * (30s on this server's php8.2-fpm pool), and it also tied up one of only
 * 15 shared php-fpm workers on this box for the whole send. A real queue
 * worker has neither problem: CLI PHP has no execution-time cap, and it
 * never touches the web-serving php-fpm pool at all.
 *
 * Root cause the throttle below exists to fix: a 270-recipient WhatsApp
 * broadcast fired every send back-to-back with zero pacing and hit
 * MoSMS's own rate limit after the first ~60 ("429 Too Many Attempts"),
 * failing the remaining 210 outright. Not a fluke of that one send — the
 * loop had no throttling at all before this.
 *
 * Deliberately not tenant-scoped via auth() — a queue worker has no HTTP
 * auth context at all, so tenant/client lookups are explicit
 * withoutGlobalScopes() + stored ids, exactly like every other
 * background-style operation in this codebase (DocumentObserver,
 * CheckLicenses, etc.).
 */
class SendBroadcastJob implements ShouldQueue
{
    use Dispatchable, Queueable, InteractsWithQueue;

    /** Stay well under MoSMS's observed WhatsApp limit (~60 succeeded before every further send 429'd in under 15s). */
    private const WHATSAPP_THROTTLE_MICROSECONDS = 1_200_000;

    /** A 1000-recipient WhatsApp broadcast takes ~20 minutes at the throttle above — don't let the worker's own retry_after reclaim it as "stuck" and run it twice. */
    public int $timeout = 3600;

    public function __construct(public string $broadcastId, public array $clientIds) {}

    public function handle(): void
    {
        $broadcast = Broadcast::withoutGlobalScopes()->find($this->broadcastId);
        if (!$broadcast) {
            return;
        }

        $tenant = Tenant::withoutGlobalScopes()->find($broadcast->tenant_id);
        if (!$tenant) {
            return;
        }

        $clients = Client::withoutGlobalScopes()->whereIn('id', $this->clientIds)->get()->keyBy('id');
        $notification = new BroadcastNotification($broadcast, $tenant);
        $throttle = $broadcast->channel === 'whatsapp';

        $sentIds = $broadcast->sent_client_ids ?? [];
        $failedIds = $broadcast->failed_client_ids ?? [];
        $reasons = $broadcast->failure_reasons ?? [];

        foreach ($this->clientIds as $clientId) {
            $client = $clients->get($clientId);

            if ($client) {
                try {
                    $client->notify($notification);
                    $sentIds[] = $clientId;
                } catch (\Throwable $e) {
                    $failedIds[] = $clientId;
                    $reasons[$clientId] = $e->getMessage();
                    Log::warning("Broadcast {$broadcast->id}: send failed for client {$clientId}: {$e->getMessage()}");
                }
            } else {
                $failedIds[] = $clientId;
                $reasons[$clientId] = 'Client no longer exists.';
            }

            $broadcast->update([
                'sent_count' => count($sentIds),
                'failed_count' => count($failedIds),
                'sent_client_ids' => $sentIds,
                'failed_client_ids' => $failedIds,
                'failure_reasons' => $reasons,
            ]);

            if ($throttle) {
                usleep(self::WHATSAPP_THROTTLE_MICROSECONDS);
            }
        }
    }
}
