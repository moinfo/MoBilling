<?php

namespace App\Http\Controllers;

use App\Jobs\SendBroadcastJob;
use App\Models\Broadcast;
use App\Models\Client;
use Illuminate\Http\Request;

class BroadcastController extends Controller
{
    public function index(Request $request)
    {
        $broadcasts = Broadcast::with('sender:id,name')
            ->orderByDesc('created_at')
            ->paginate($request->input('per_page', 15));

        return response()->json($broadcasts);
    }

    public function send(Request $request)
    {
        $request->validate([
            'channel'    => 'required|in:email,sms,whatsapp,both',
            'subject'    => 'required_if:channel,email,both|nullable|string|max:255',
            'body'       => 'required_if:channel,email,both|nullable|string',
            'sms_body'   => 'required_if:channel,sms,both|nullable|string|max:160',
            'whatsapp_body' => 'required_if:channel,whatsapp|nullable|string|max:4096',
            // Capped at 2MB — this server's upload_max_filesize is 2M, so anything larger
            // never reaches this validation (PHP drops it before Laravel sees the request).
            'whatsapp_image' => 'nullable|image|mimes:jpeg,png,webp|max:2048',
            'client_ids' => 'nullable|array',
            'client_ids.*' => 'uuid|exists:clients,id',
        ]);

        $channel = $request->channel;

        // Build eligible client query (BelongsToTenant auto-scopes)
        $query = Client::query();

        if ($request->filled('client_ids')) {
            $query->whereIn('id', $request->client_ids);
        }

        // Filter to clients who can receive on the chosen channel
        if ($channel === 'email') {
            $query->whereNotNull('email')->where('email', '!=', '');
        } elseif (in_array($channel, ['sms', 'whatsapp'], true)) {
            $query->whereNotNull('phone')->where('phone', '!=', '');
        } else {
            // 'both' — need at least one contact method
            $query->where(function ($q) {
                $q->where(function ($q2) {
                    $q2->whereNotNull('email')->where('email', '!=', '');
                })->orWhere(function ($q2) {
                    $q2->whereNotNull('phone')->where('phone', '!=', '');
                });
            });
        }

        $clients = $query->get();

        $imagePath = null;
        if ($request->hasFile('whatsapp_image')) {
            $imagePath = $request->file('whatsapp_image')->store('whatsapp-posters', 'public');
        }

        // Create broadcast record
        $broadcast = Broadcast::create([
            'sent_by'          => $request->user()->id,
            'client_ids'       => $request->client_ids,
            'total_recipients' => $clients->count(),
            'channel'          => $channel,
            'subject'          => $request->subject,
            'body'             => $request->body,
            'sms_body'         => $request->sms_body,
            'whatsapp_body'    => $request->whatsapp_body,
            'whatsapp_image_path' => $imagePath,
            'sent_count'       => 0,
            'failed_count'     => 0,
        ]);

        // Runs on the dedicated 'broadcasts' queue worker — see SendBroadcastJob
        // for why (WhatsApp sends are throttled, so a large list can genuinely
        // take minutes, well past anything safe to run inline on a web worker).
        SendBroadcastJob::dispatch($broadcast->id, $clients->pluck('id')->all())
            ->onConnection('database')
            ->onQueue('broadcasts');

        return response()->json([
            'message'          => 'Broadcast started — sending in the background. Refresh History for live progress.',
            'broadcast_id'     => $broadcast->id,
            'total_recipients' => $clients->count(),
        ], 202);
    }

    /** List the clients a broadcast did or didn't reach — for "which ones failed, and why?" */
    public function recipients(Request $request, Broadcast $broadcast)
    {
        $status = $request->input('status', 'failed');
        $ids = $status === 'sent' ? ($broadcast->sent_client_ids ?? []) : ($broadcast->failed_client_ids ?? []);
        $reasons = $broadcast->failure_reasons ?? [];

        $clients = Client::withoutGlobalScopes()
            ->whereIn('id', $ids)
            ->get(['id', 'name', 'email', 'phone'])
            ->keyBy('id');

        // Every id gets a row even if the client was since deleted — a
        // failure is still worth showing, not silently dropped.
        $data = collect($ids)->map(function ($id) use ($clients, $reasons, $status) {
            $client = $clients->get($id);

            return [
                'id' => $id,
                'name' => $client->name ?? 'Unknown client (removed)',
                'email' => $client->email ?? null,
                'phone' => $client->phone ?? null,
                'reason' => $status === 'failed' ? ($reasons[$id] ?? null) : null,
            ];
        })->values();

        return response()->json(['data' => $data]);
    }

    /** Re-send the exact same content to only the recipients who failed last time — never the ones already reached. */
    public function resendFailed(Request $request, Broadcast $broadcast)
    {
        $failedIds = $broadcast->failed_client_ids ?? [];
        if (empty($failedIds)) {
            return response()->json(['message' => 'No failed recipients to resend to.'], 422);
        }

        $retry = Broadcast::create([
            'sent_by'          => $request->user()->id,
            'client_ids'       => $failedIds,
            'total_recipients' => count($failedIds),
            'channel'          => $broadcast->channel,
            'subject'          => $broadcast->subject,
            'body'             => $broadcast->body,
            'sms_body'         => $broadcast->sms_body,
            'whatsapp_body'    => $broadcast->whatsapp_body,
            'whatsapp_image_path' => $broadcast->whatsapp_image_path,
            'sent_count'       => 0,
            'failed_count'     => 0,
            'retry_of_broadcast_id' => $broadcast->id,
        ]);

        SendBroadcastJob::dispatch($retry->id, $failedIds)
            ->onConnection('database')
            ->onQueue('broadcasts');

        return response()->json([
            'message'          => 'Resend started for ' . count($failedIds) . ' recipient(s) — refresh History for live progress.',
            'broadcast_id'     => $retry->id,
            'total_recipients' => count($failedIds),
        ], 202);
    }
}
