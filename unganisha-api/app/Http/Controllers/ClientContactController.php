<?php

namespace App\Http\Controllers;

use App\Models\Client;
use App\Models\ClientContact;
use Illuminate\Http\Request;

/**
 * WHMCS-style "Additional Contacts" — secondary people at the client's
 * company, distinct from the primary Client record and from ClientUser
 * (portal login credentials). Mirrors ClientPortalUserController's shape.
 */
class ClientContactController extends Controller
{
    public function index(Request $request, Client $client)
    {
        $contacts = ClientContact::where('client_id', $client->id)
            ->orderBy('name')
            ->get();

        return response()->json(['data' => $contacts]);
    }

    public function store(Request $request, Client $client)
    {
        $data = $request->validate([
            'name'  => 'required|string|max:255',
            'email' => 'nullable|email|max:255',
            'phone' => 'nullable|string|max:20',
            'role'  => 'nullable|string|max:100',
            'notes' => 'nullable|string|max:2000',
        ]);

        $contact = ClientContact::create([
            ...$data,
            'client_id' => $client->id,
            'tenant_id' => $request->user()->tenant_id,
        ]);

        return response()->json(['data' => $contact, 'message' => 'Contact added.'], 201);
    }

    public function update(Request $request, Client $client, ClientContact $contact)
    {
        if ($contact->client_id !== $client->id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $data = $request->validate([
            'name'  => 'sometimes|string|max:255',
            'email' => 'nullable|email|max:255',
            'phone' => 'nullable|string|max:20',
            'role'  => 'nullable|string|max:100',
            'notes' => 'nullable|string|max:2000',
        ]);

        $contact->update($data);

        return response()->json(['data' => $contact->fresh(), 'message' => 'Contact updated.']);
    }

    public function destroy(Request $request, Client $client, ClientContact $contact)
    {
        if ($contact->client_id !== $client->id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $contact->delete();

        return response()->json(['message' => 'Contact removed.']);
    }
}
