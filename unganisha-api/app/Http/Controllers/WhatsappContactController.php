<?php

namespace App\Http\Controllers;

use App\Models\Client;
use App\Models\WhatsappContact;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

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
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'name'               => 'required|string|max:255',
            'phone'              => [
                'required', 'string', 'max:50',
                Rule::unique('whatsapp_contacts')->where('tenant_id', $tenantId),
            ],
            'label'              => 'required|in:lead,new_customer,new_order,follow_up,pending_payment,paid,order_complete',
            'is_important'       => 'boolean',
            'source'             => 'required|in:whatsapp_ad,instagram,facebook,social_media,direct,referral,other',
            'campaign_id'        => 'nullable|uuid|exists:whatsapp_campaigns,id',
            'notes'              => 'nullable|string',
            'services'           => 'nullable|array',
            'services.*'         => 'string',
            'next_followup_date' => 'nullable|date',
            'assigned_to'        => 'nullable|uuid|exists:users,id',
            'client_id'          => 'nullable|uuid|exists:clients,id',
        ]);

        // Check if phone already belongs to an existing client
        $existingClient = Client::where('tenant_id', $tenantId)
            ->where('phone', $data['phone'])
            ->first(['id', 'name', 'email', 'phone']);

        $contact = WhatsappContact::create($data);

        $response = $contact->load(['client:id,name', 'assignedUser:id,name', 'campaign:id,name']);

        return response()->json([
            'contact'          => $response,
            'existing_client'  => $existingClient, // null if not found, client data if match
        ], 201);
    }

    public function update(Request $request, WhatsappContact $whatsappContact)
    {
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'name'               => 'sometimes|string|max:255',
            'phone'              => [
                'sometimes', 'string', 'max:50',
                Rule::unique('whatsapp_contacts')->where('tenant_id', $tenantId)->ignore($whatsappContact->id),
            ],
            'label'              => 'sometimes|in:lead,new_customer,new_order,follow_up,pending_payment,paid,order_complete',
            'is_important'       => 'boolean',
            'source'             => 'sometimes|in:whatsapp_ad,instagram,facebook,social_media,direct,referral,other',
            'campaign_id'        => 'nullable|uuid|exists:whatsapp_campaigns,id',
            'notes'              => 'nullable|string',
            'services'           => 'nullable|array',
            'services.*'         => 'string',
            'next_followup_date' => 'nullable|date',
            'assigned_to'        => 'nullable|uuid|exists:users,id',
            'client_id'          => 'nullable|uuid|exists:clients,id',
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
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'client_id'    => 'nullable|uuid|exists:clients,id',
            'client_name'  => 'required_without:client_id|string|max:255',
            'client_email' => 'nullable|email|max:255',
            'client_phone' => 'nullable|string|max:50',
        ]);

        if (!empty($data['client_id'])) {
            $clientId = $data['client_id'];
        } else {
            // Use contact phone if client_phone not given, but check it's not already taken
            $phone = $data['client_phone'] ?? $whatsappContact->phone;
            $phoneTaken = Client::where('tenant_id', $tenantId)->where('phone', $phone)->exists();

            $client = Client::create([
                'name'  => $data['client_name'],
                'email' => $data['client_email'] ?? null,
                'phone' => $phoneTaken ? null : $phone,
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
        $total     = WhatsappContact::count();
        $byLabel   = WhatsappContact::selectRaw('label, COUNT(*) as count')->groupBy('label')->pluck('count', 'label');
        $bySource  = WhatsappContact::selectRaw('source, COUNT(*) as count')->groupBy('source')->pluck('count', 'source');
        $converted = WhatsappContact::whereNotNull('client_id')->count();

        return response()->json([
            'total'     => $total,
            'converted' => $converted,
            'by_label'  => $byLabel,
            'by_source' => $bySource,
        ]);
    }
}
