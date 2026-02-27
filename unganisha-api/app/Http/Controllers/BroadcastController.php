<?php

namespace App\Http\Controllers;

use App\Models\Broadcast;
use App\Models\Client;
use App\Notifications\BroadcastNotification;
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
            'channel'    => 'required|in:email,sms,both',
            'subject'    => 'required_if:channel,email,both|nullable|string|max:255',
            'body'       => 'required_if:channel,email,both|nullable|string',
            'sms_body'   => 'required_if:channel,sms,both|nullable|string|max:160',
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
        } elseif ($channel === 'sms') {
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
        ]);

        $tenant = $request->user()->tenant()->withoutGlobalScopes()->first();
        $notification = new BroadcastNotification($broadcast, $tenant);

        $sent = 0;
        $failed = 0;

        foreach ($clients as $client) {
            try {
                $client->notify($notification);
                $sent++;
            } catch (\Throwable $e) {
                $failed++;
            }
        }

        $broadcast->update([
            'sent_count'   => $sent,
            'failed_count' => $failed,
        ]);

        return response()->json([
            'message'          => 'Broadcast sent',
            'broadcast_id'     => $broadcast->id,
            'total_recipients' => $clients->count(),
            'sent_count'       => $sent,
            'failed_count'     => $failed,
        ]);
    }
}
