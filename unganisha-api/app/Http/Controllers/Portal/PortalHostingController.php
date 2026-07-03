<?php

namespace App\Http\Controllers\Portal;

use App\Exceptions\WhmApiException;
use App\Http\Controllers\Controller;
use App\Models\HostingAccount;
use App\Services\WhmService;
use Illuminate\Http\Request;

class PortalHostingController extends Controller
{
    /** The authed client's hosting accounts (safe fields only). */
    public function index(Request $request)
    {
        $clientId = $request->user()->client_id;

        $accounts = HostingAccount::with(['server:id,name,hostname', 'subscription:id,client_id,label,expire_date'])
            ->whereHas('subscription', fn ($q) => $q->where('client_id', $clientId))
            ->whereNotIn('status', ['terminated'])
            ->orderBy('domain')
            ->get()
            ->map(fn ($a) => [
                'id'              => $a->id,
                'domain'          => $a->domain,
                'cpanel_username' => $a->cpanel_username,
                'package'         => $a->meta['plan'] ?? $a->package,
                'status'          => $a->status,
                'disk_used'       => $a->meta['disk_used'] ?? null,
                'disk_limit'      => $a->meta['disk_limit'] ?? null,
                'server_hostname' => $a->server?->hostname,
                'expires_at'      => $a->subscription?->expire_date?->toDateString(),
            ]);

        return response()->json(['data' => $accounts]);
    }

    /** One-time cPanel login URL. Portal admins only — SSO grants full hosting control. */
    public function sso(Request $request, HostingAccount $hostingAccount)
    {
        $user = $request->user();

        abort_unless($hostingAccount->subscription?->client_id === $user->client_id, 403);
        abort_unless($user->role === 'admin', 403, 'Only portal administrators can open cPanel.');
        abort_unless($hostingAccount->status === 'active', 422, 'This hosting account is not active.');

        try {
            $url = (new WhmService($hostingAccount->server))
                ->forAccount($hostingAccount->id)
                ->ssoUrl($hostingAccount->cpanel_username);

            return response()->json(['url' => $url]);
        } catch (WhmApiException $e) {
            return response()->json(['message' => 'Could not open cPanel right now. Please try again later.'], 422);
        }
    }
}
