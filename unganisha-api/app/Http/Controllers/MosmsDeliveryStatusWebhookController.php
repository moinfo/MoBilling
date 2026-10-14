<?php

namespace App\Http\Controllers;

use App\Models\CommunicationLog;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * MoSMS pushes this whenever a message it sent on our behalf (SMS or WhatsApp)
 * gets a real delivery-status update from the carrier/WhatsApp — upgrading a
 * CommunicationLog row's `status` ("the API call succeeded") with the actual
 * outcome. Matched by `mosms_message_id` (SMS, known synchronously at send
 * time) or `client_ref` (WhatsApp, which MoSMS sends asynchronously — we mint
 * this ourselves at send time and MoSMS just echoes it back here).
 */
class MosmsDeliveryStatusWebhookController extends Controller
{
    public function update(Request $request): JsonResponse
    {
        if (!hash_equals((string) config('services.mosms.inbound_webhook_secret'), (string) $request->secret)) {
            return response()->json(['message' => 'Unauthorized.'], 401);
        }

        $request->validate([
            'status' => 'required|string',
            'delivered_at' => 'nullable|date',
            'error' => 'nullable|string',
            'mosms_message_id' => 'nullable|string',
            'client_ref' => 'nullable|string',
        ]);

        if (!$request->filled('mosms_message_id') && !$request->filled('client_ref')) {
            return response()->json(['message' => 'mosms_message_id or client_ref is required.'], 422);
        }

        $log = CommunicationLog::withoutGlobalScopes()
            ->where(function ($q) use ($request) {
                if ($request->filled('mosms_message_id')) {
                    $q->orWhere('mosms_message_id', $request->mosms_message_id);
                }
                if ($request->filled('client_ref')) {
                    $q->orWhere('client_ref', $request->client_ref);
                }
            })
            ->latest('created_at')
            ->first();

        if (!$log) {
            // Not necessarily a problem — e.g. a direct-Meta tenant's send has no
            // mosms_message_id/client_ref to match in the first place.
            return response()->json(['message' => 'No matching communication log.'], 404);
        }

        $log->update([
            'delivery_status' => $request->status,
            'delivered_at' => $request->delivered_at,
            'delivery_error' => $request->error,
        ]);

        return response()->json(['message' => 'Updated.']);
    }
}
