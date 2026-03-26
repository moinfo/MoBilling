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

    public function impersonate(Request $request, Client $client)
    {
        $portalUser = ClientUser::where('client_id', $client->id)
            ->where('is_active', true)
            ->orderByRaw("FIELD(role, 'admin', 'viewer')")
            ->first();

        // Auto-create portal user if none exists
        if (!$portalUser) {
            if (!$client->email) {
                return response()->json(['message' => 'Client has no email address. Add an email first.'], 422);
            }

            $portalUser = ClientUser::create([
                'client_id' => $client->id,
                'tenant_id' => $request->user()->tenant_id,
                'name' => $client->name,
                'email' => $client->email,
                'phone' => $client->phone,
                'password' => 'portal-' . str()->random(12),
                'role' => 'admin',
            ]);
        }

        $token = $portalUser->createToken('impersonate')->plainTextToken;
        $portalUser->load('client', 'tenant');

        return response()->json([
            'user' => $portalUser,
            'token' => $token,
            'user_type' => 'client',
            'permissions' => $portalUser->isPortalAdmin()
                ? ['portal.view', 'portal.profile', 'portal.users']
                : ['portal.view', 'portal.profile'],
            'message' => "Logged in as {$portalUser->name} ({$portalUser->email})",
        ]);
    }

    public function changePassword(Request $request, Client $client)
    {
        $request->validate([
            'portal_user_id' => 'nullable|uuid',
            'password' => 'required|min:8',
        ]);

        // If portal_user_id specified, change that user's password; otherwise change the first admin
        if ($request->portal_user_id) {
            $portalUser = ClientUser::where('client_id', $client->id)
                ->where('id', $request->portal_user_id)
                ->first();
        } else {
            $portalUser = ClientUser::where('client_id', $client->id)
                ->orderByRaw("FIELD(role, 'admin', 'viewer')")
                ->first();
        }

        // Auto-create portal user if none exists
        if (!$portalUser) {
            if (!$client->email) {
                return response()->json(['message' => 'Client has no email address. Add an email first.'], 422);
            }

            $portalUser = ClientUser::create([
                'client_id' => $client->id,
                'tenant_id' => $request->user()->tenant_id,
                'name' => $client->name,
                'email' => $client->email,
                'phone' => $client->phone,
                'password' => $request->password,
                'role' => 'admin',
            ]);

            return response()->json([
                'message' => "Portal account created for {$portalUser->name} ({$portalUser->email})",
                'created' => true,
            ]);
        }

        $portalUser->update(['password' => $request->password]);

        return response()->json([
            'message' => "Password changed for {$portalUser->name} ({$portalUser->email})",
        ]);
    }
}
