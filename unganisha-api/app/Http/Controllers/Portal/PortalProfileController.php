<?php

namespace App\Http\Controllers\Portal;

use App\Http\Controllers\Controller;
use App\Models\ClientUser;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

class PortalProfileController extends Controller
{
    public function show(Request $request)
    {
        $clientUser = $request->user();
        $clientUser->load('client');

        return response()->json([
            'user' => $clientUser,
            'client' => $clientUser->client,
        ]);
    }

    public function update(Request $request)
    {
        $clientUser = $request->user();

        $data = $request->validate([
            'name' => 'sometimes|string|max:255',
            'phone' => 'nullable|string|max:20',
        ]);

        $clientUser->update($data);

        return response()->json([
            'message' => 'Profile updated successfully.',
            'user' => $clientUser->fresh(),
        ]);
    }

    public function changePassword(Request $request)
    {
        $request->validate([
            'current_password' => 'required',
            'password' => 'required|min:8|confirmed',
        ]);

        $clientUser = $request->user();

        if (!Hash::check($request->current_password, $clientUser->password)) {
            throw ValidationException::withMessages([
                'current_password' => ['The current password is incorrect.'],
            ]);
        }

        $clientUser->update(['password' => $request->password]);

        return response()->json(['message' => 'Password changed successfully.']);
    }

    // Portal user management (only for portal admins)
    public function listUsers(Request $request)
    {
        $clientUser = $request->user();

        if (!$clientUser->isPortalAdmin()) {
            return response()->json(['message' => 'Forbidden'], 403);
        }

        $users = ClientUser::where('client_id', $clientUser->client_id)
            ->orderBy('name')
            ->get();

        return response()->json(['data' => $users]);
    }

    public function storeUser(Request $request)
    {
        $clientUser = $request->user();

        if (!$clientUser->isPortalAdmin()) {
            return response()->json(['message' => 'Forbidden'], 403);
        }

        $data = $request->validate([
            'name' => 'required|string|max:255',
            'email' => 'required|email|max:255',
            'password' => 'required|min:8',
            'phone' => 'nullable|string|max:20',
            'role' => 'required|in:admin,viewer',
        ]);

        // Check email uniqueness within tenant
        $exists = ClientUser::where('email', $data['email'])
            ->where('tenant_id', $clientUser->tenant_id)
            ->exists();

        if ($exists) {
            throw ValidationException::withMessages([
                'email' => ['This email is already in use.'],
            ]);
        }

        $newUser = ClientUser::create([
            ...$data,
            'client_id' => $clientUser->client_id,
            'tenant_id' => $clientUser->tenant_id,
        ]);

        return response()->json(['data' => $newUser, 'message' => 'User created successfully.'], 201);
    }

    public function updateUser(Request $request, ClientUser $portalUser)
    {
        $clientUser = $request->user();

        if (!$clientUser->isPortalAdmin() || $portalUser->client_id !== $clientUser->client_id) {
            return response()->json(['message' => 'Forbidden'], 403);
        }

        $data = $request->validate([
            'name' => 'sometimes|string|max:255',
            'phone' => 'nullable|string|max:20',
            'role' => 'sometimes|in:admin,viewer',
            'is_active' => 'sometimes|boolean',
        ]);

        $portalUser->update($data);

        return response()->json(['data' => $portalUser->fresh(), 'message' => 'User updated.']);
    }

    public function deleteUser(Request $request, ClientUser $portalUser)
    {
        $clientUser = $request->user();

        if (!$clientUser->isPortalAdmin() || $portalUser->client_id !== $clientUser->client_id) {
            return response()->json(['message' => 'Forbidden'], 403);
        }

        if ($portalUser->id === $clientUser->id) {
            return response()->json(['message' => 'You cannot delete your own account.'], 422);
        }

        $portalUser->delete();

        return response()->json(['message' => 'User deleted.']);
    }
}
