<?php

namespace App\Http\Controllers;

use App\Models\Client;
use App\Models\ClientUser;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

class ClientPortalUserController extends Controller
{
    public function index(Request $request, Client $client)
    {
        $users = ClientUser::where('client_id', $client->id)
            ->orderBy('name')
            ->get();

        return response()->json(['data' => $users]);
    }

    public function store(Request $request, Client $client)
    {
        $data = $request->validate([
            'name' => 'required|string|max:255',
            'email' => 'required|email|max:255',
            'password' => 'required|min:8',
            'phone' => 'nullable|string|max:20',
            'role' => 'required|in:admin,viewer',
        ]);

        $tenantId = $request->user()->tenant_id;

        $exists = ClientUser::where('email', $data['email'])
            ->where('tenant_id', $tenantId)
            ->exists();

        if ($exists) {
            throw ValidationException::withMessages([
                'email' => ['This email is already in use.'],
            ]);
        }

        $portalUser = ClientUser::create([
            ...$data,
            'client_id' => $client->id,
            'tenant_id' => $tenantId,
        ]);

        return response()->json(['data' => $portalUser, 'message' => 'Portal user created.'], 201);
    }

    public function update(Request $request, Client $client, ClientUser $portalUser)
    {
        if ($portalUser->client_id !== $client->id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $data = $request->validate([
            'name' => 'sometimes|string|max:255',
            'phone' => 'nullable|string|max:20',
            'role' => 'sometimes|in:admin,viewer',
            'is_active' => 'sometimes|boolean',
            'password' => 'nullable|min:8',
        ]);

        // Only update password if provided
        if (empty($data['password'])) {
            unset($data['password']);
        }

        $portalUser->update($data);

        return response()->json(['data' => $portalUser->fresh(), 'message' => 'Portal user updated.']);
    }

    public function destroy(Request $request, Client $client, ClientUser $portalUser)
    {
        if ($portalUser->client_id !== $client->id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $portalUser->delete();

        return response()->json(['message' => 'Portal user deleted.']);
    }
}
