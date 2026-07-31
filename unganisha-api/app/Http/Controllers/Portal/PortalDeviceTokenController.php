<?php

namespace App\Http\Controllers\Portal;

use App\Http\Controllers\Controller;
use App\Models\DeviceToken;
use Illuminate\Http\Request;

/**
 * Mobile app push-token lifecycle: register on login / token refresh,
 * unregister on sign-out.
 */
class PortalDeviceTokenController extends Controller
{
    public function store(Request $request)
    {
        $data = $request->validate([
            'token'    => 'required|string|max:255',
            'platform' => 'nullable|in:ios,android',
        ]);

        $user = $request->user();

        // A device has one owner: if this token was registered by a previous
        // sign-in on the same phone, it must move — not duplicate.
        DeviceToken::updateOrCreate(
            ['token' => $data['token']],
            [
                'tenant_id'    => $user->tenant_id,
                'owner_type'   => $user::class,
                'owner_id'     => $user->id,
                'platform'     => $data['platform'] ?? null,
                'app'          => 'client_portal',
                'last_seen_at' => now(),
            ]
        );

        return response()->json(['message' => 'Device registered.']);
    }

    public function destroy(Request $request)
    {
        $data = $request->validate(['token' => 'required|string|max:255']);

        $user = $request->user();

        DeviceToken::where('token', $data['token'])
            ->where('owner_type', $user::class)
            ->where('owner_id', $user->id)
            ->delete();

        return response()->json(['message' => 'Device unregistered.']);
    }
}
