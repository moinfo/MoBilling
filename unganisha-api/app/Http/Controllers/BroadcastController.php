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
            'sent_count'       => 0,
            'failed_count'     => 0,
        ]);

        // Runs after the response is returned — see SendBroadcastJob for why
        // (no queue worker of this app's own, and WhatsApp sends are
        // throttled, so this can genuinely take minutes for a large list).
        SendBroadcastJob::dispatch($broadcast->id, $clients->pluck('id')->all())->afterResponse();

        return response()->json([
            'message'          => 'Broadcast started — sending in the background. Refresh History for live progress.',
            'broadcast_id'     => $broadcast->id,
            'total_recipients' => $clients->count(),
        ], 202);
    }

    /** List the clients a broadcast did or didn't reach — for "which ones failed?" */
    public function recipients(Request $request, Broadcast $broadcast)
    {
        $status = $request->input('status', 'failed');
        $ids = $status === 'sent' ? ($broadcast->sent_client_ids ?? []) : ($broadcast->failed_client_ids ?? []);

        $clients = Client::withoutGlobalScopes()
            ->whereIn('id', $ids)
            ->get(['id', 'name', 'email', 'phone']);

        return response()->json(['data' => $clients]);
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
            'sent_count'       => 0,
            'failed_count'     => 0,
            'retry_of_broadcast_id' => $broadcast->id,
        ]);

        SendBroadcastJob::dispatch($retry->id, $failedIds)->afterResponse();

        return response()->json([
            'message'          => 'Resend started for ' . count($failedIds) . ' recipient(s) — refresh History for live progress.',
            'broadcast_id'     => $retry->id,
            'total_recipients' => count($failedIds),
        ], 202);
    }
}
