<?php

namespace App\Http\Controllers;

use App\Models\Client;
use App\Models\WhatsappContact;
use Illuminate\Http\Request;

class WhatsappContactController extends Controller
{
    public function index(Request $request)
    {
        $query = WhatsappContact::with(['client:id,name', 'assignedUser:id,name', 'campaign:id,name'])
            ->latest();

        if ($request->label) {
            $query->where('label', $request->label);
        }
        if ($request->source) {
            $query->where('source', $request->source);
        }
        if ($request->search) {
            $query->where(function ($q) use ($request) {
                $q->where('name', 'like', "%{$request->search}%")
                  ->orWhere('phone', 'like', "%{$request->search}%");
            });
        }

        return response()->json($query->with(['campaign:id,name'])->get());
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'name'              => 'required|string|max:255',
            'phone'             => 'required|string|max:50',
            'label'             => 'required|in:lead,new_customer,new_order,follow_up,pending_payment,paid,order_complete',
            'is_important'      => 'boolean',
            'source'            => 'required|in:whatsapp_ad,direct,referral,other',
            'campaign_id'       => 'nullable|uuid|exists:whatsapp_campaigns,id',
            'notes'             => 'nullable|string',
            'next_followup_date'=> 'nullable|date',
            'assigned_to'       => 'nullable|uuid|exists:users,id',
            'client_id'         => 'nullable|uuid|exists:clients,id',
        ]);

        $contact = WhatsappContact::create($data);

        return response()->json($contact->load(['client:id,name', 'assignedUser:id,name', 'campaign:id,name']), 201);
    }

    public function update(Request $request, WhatsappContact $whatsappContact)
    {
        $data = $request->validate([
            'name'              => 'sometimes|string|max:255',
            'phone'             => 'sometimes|string|max:50',
            'label'             => 'sometimes|in:lead,new_customer,new_order,follow_up,pending_payment,paid,order_complete',
            'is_important'      => 'boolean',
            'source'            => 'sometimes|in:whatsapp_ad,direct,referral,other',
            'campaign_id'       => 'nullable|uuid|exists:whatsapp_campaigns,id',
            'notes'             => 'nullable|string',
            'next_followup_date'=> 'nullable|date',
            'assigned_to'       => 'nullable|uuid|exists:users,id',
            'client_id'         => 'nullable|uuid|exists:clients,id',
        ]);

        $whatsappContact->update($data);

        return response()->json($whatsappContact->load(['client:id,name', 'assignedUser:id,name', 'campaign:id,name']));
    }

    public function destroy(WhatsappContact $whatsappContact)
    {
        $whatsappContact->delete();
        return response()->json(null, 204);
    }

    // Convert lead to client
    public function convertToClient(Request $request, WhatsappContact $whatsappContact)
    {
        $data = $request->validate([
            'client_id' => 'nullable|uuid|exists:clients,id', // link existing client
            // fields for new client
            'client_name'  => 'required_without:client_id|string|max:255',
            'client_email' => 'nullable|email|max:255',
            'client_phone' => 'nullable|string|max:50',
        ]);

        if (!empty($data['client_id'])) {
            $clientId = $data['client_id'];
        } else {
            $client = Client::create([
                'name'  => $data['client_name'],
                'email' => $data['client_email'] ?? null,
                'phone' => $data['client_phone'] ?? $whatsappContact->phone,
            ]);
            $clientId = $client->id;
        }

        $whatsappContact->update([
            'client_id' => $clientId,
            'label'     => 'new_customer',
        ]);

        return response()->json($whatsappContact->load(['client:id,name', 'assignedUser:id,name']));
    }

    public function stats()
    {
        $total = WhatsappContact::count();
        $byLabel = WhatsappContact::selectRaw('label, COUNT(*) as count')
            ->groupBy('label')
            ->pluck('count', 'label');
        $bySource = WhatsappContact::selectRaw('source, COUNT(*) as count')
            ->groupBy('source')
            ->pluck('count', 'source');
        $converted = WhatsappContact::whereNotNull('client_id')->count();

        return response()->json([
            'total'     => $total,
            'converted' => $converted,
            'by_label'  => $byLabel,
            'by_source' => $bySource,
        ]);
    }
}
