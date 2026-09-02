<?php

namespace App\Jobs;

use App\Models\Broadcast;
use App\Models\Client;
use App\Models\Tenant;
use App\Notifications\BroadcastNotification;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Support\Facades\Log;

/**
 * Does the actual per-recipient sending for a Broadcast, dispatched via
 * ->afterResponse() rather than a real queue — this app runs
 * QUEUE_CONNECTION=sync with no queue worker of its own (the one
 * `queue:work` process on this box belongs to the separate MoSMS app), so
 * a real ShouldQueue dispatch would just run inline in the request like
 * everything else on 'sync'. afterResponse() instead lets the HTTP
 * response return immediately while this keeps running in the same
 * php-fpm worker — needed because WhatsApp sends are throttled below,
 * and a few hundred recipients at ~1/sec would blow well past nginx's
 * request timeout if done synchronously before responding.
 *
 * Root cause this exists to fix: a 270-recipient WhatsApp broadcast fired
 * every send back-to-back with zero pacing and hit MoSMS's own rate
 * limit after the first ~60 ("429 Too Many Attempts"), failing the
 * remaining 210 outright. Not a fluke of that one send — the loop had no
 * throttling at all before this.
 *
 * Deliberately not tenant-scoped via auth() — this may run after the
 * request's auth context is gone, so tenant/client lookups are explicit
 * withoutGlobalScopes() + stored ids, exactly like every other
 * background-style operation in this codebase (DocumentObserver,
 * CheckLicenses, etc.).
 */
class SendBroadcastJob
{
    use Dispatchable;

    /** Stay well under MoSMS's observed WhatsApp limit (~60 succeeded before every further send 429'd in under 15s). */
    private const WHATSAPP_THROTTLE_MICROSECONDS = 1_200_000;

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
