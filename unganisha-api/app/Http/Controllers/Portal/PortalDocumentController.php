<?php

namespace App\Http\Controllers\Portal;

use App\Http\Controllers\Controller;
use App\Models\Document;
use App\Notifications\InvoiceSentNotification;
use Illuminate\Http\Request;

class PortalDocumentController extends Controller
{
    public function index(Request $request)
    {
        $clientId = $request->user()->client_id;
        $type = $request->get('type', 'invoice');

        $query = Document::where('client_id', $clientId)
            ->where('type', $type)
            ->whereNotIn('status', ['draft', 'cancelled'])
            ->with('items')
            ->orderByDesc('date');

        if ($request->filled('status')) {
            $query->where('status', $request->status);
        }

        if ($request->filled('search')) {
            $query->where('document_number', 'like', "%{$request->search}%");
        }

        return response()->json($query->paginate($request->get('per_page', 20)));
    }

    public function show(Request $request, Document $document)
    {
        $clientId = $request->user()->client_id;

        if ($document->client_id !== $clientId) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $document->load('items', 'payments');

        return response()->json([
            'data' => array_merge($document->toArray(), [
                'paid_amount' => (float) $document->paid_amount,
                'balance_due' => (float) $document->balance_due,
            ]),
        ]);
    }

    public function resend(Request $request, Document $document)
    {
        $clientId = $request->user()->client_id;

        if ($document->client_id !== $clientId) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $document->load('client');
        $document->client->notify(new InvoiceSentNotification($document));

        return response()->json(['message' => 'Document sent to your email.']);
    }
}
