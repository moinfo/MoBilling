<?php

namespace App\Http\Controllers;

use App\Models\ClientUser;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Visibility into who's actually still logged in. Sanctum tokens never
 * expire here (config/sanctum.php `expiration` => null) and deactivating an
 * account only blocks future logins, not tokens already issued — so this is
 * the only place staff can see (and revoke) sessions that are stale, belong
 * to a deactivated account, or were never used at all.
 */
class SessionController extends Controller
{
    public function index(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $staffTokens = DB::table('personal_access_tokens')
            ->join('users', function ($j) {
                $j->on('users.id', '=', 'personal_access_tokens.tokenable_id')
                    ->where('personal_access_tokens.tokenable_type', User::class);
            })
            ->where('users.tenant_id', $tenantId)
            ->select([
                'personal_access_tokens.id',
                'personal_access_tokens.name as token_name',
                'personal_access_tokens.last_used_at',
                'personal_access_tokens.created_at',
                'users.id as owner_id',
                'users.name as owner_name',
                'users.email as owner_email',
                'users.is_active as owner_active',
                DB::raw("'staff' as owner_type"),
                DB::raw('NULL as client_name'),
                DB::raw('NULL as client_status'),
            ]);

        $clientTokens = DB::table('personal_access_tokens')
            ->join('client_users', function ($j) {
                $j->on('client_users.id', '=', 'personal_access_tokens.tokenable_id')
                    ->where('personal_access_tokens.tokenable_type', ClientUser::class);
            })
            ->leftJoin('clients', 'clients.id', '=', 'client_users.client_id')
            ->where('client_users.tenant_id', $tenantId)
            ->select([
                'personal_access_tokens.id',
                'personal_access_tokens.name as token_name',
                'personal_access_tokens.last_used_at',
                'personal_access_tokens.created_at',
                'client_users.id as owner_id',
                'client_users.name as owner_name',
                'client_users.email as owner_email',
                'client_users.is_active as owner_active',
                DB::raw("'client' as owner_type"),
                'clients.name as client_name',
                'clients.status as client_status',
            ]);

        $rows = $staffTokens->unionAll($clientTokens)
            ->orderByDesc('last_used_at')
            ->get();

        if ($request->filled('type')) {
            $rows = $rows->where('owner_type', $request->string('type'));
        }
        if ($request->has('status')) {
            // 'inactive' = owner_active is false, OR (client) the client record itself isn't active.
            $wantActive = $request->boolean('status');
            $rows = $rows->filter(fn ($r) => $this->isEffectivelyActive($r) === $wantActive)->values();
        }
        if ($request->filled('search')) {
            $s = strtolower($request->string('search'));
            $rows = $rows->filter(fn ($r) =>
                str_contains(strtolower($r->owner_name ?? ''), $s)
                || str_contains(strtolower($r->owner_email ?? ''), $s)
                || str_contains(strtolower($r->client_name ?? ''), $s))->values();
        }

        return response()->json([
            'data' => $rows->map(fn ($r) => [
                'id'               => $r->id,
                'token_name'       => $r->token_name,
                'owner_type'       => $r->owner_type,
                'owner_id'         => $r->owner_id,
                'owner_name'       => $r->owner_name,
                'owner_email'      => $r->owner_email,
                'owner_active'     => (bool) $r->owner_active,
                'client_name'      => $r->client_name,
                'client_status'    => $r->client_status,
                'effectively_active' => $this->isEffectivelyActive($r),
                'last_used_at'     => $r->last_used_at,
                'created_at'       => $r->created_at,
                'never_used'       => $r->last_used_at === null,
            ])->values(),
            'summary' => [
                'total'       => $rows->count(),
                'never_used'  => $rows->where('last_used_at', null)->count(),
                'on_inactive' => $rows->filter(fn ($r) => !$this->isEffectivelyActive($r))->count(),
            ],
        ]);
    }

    private function isEffectivelyActive(object $r): bool
    {
        if (!$r->owner_active) {
            return false;
        }
        if ($r->owner_type === 'client' && $r->client_status && $r->client_status !== 'active') {
            return false;
        }
        return true;
    }

    /** Force-logout a single session. */
    public function destroy(Request $request, string $id)
    {
        $tenantId = auth()->user()->tenant_id;

        $deleted = DB::table('personal_access_tokens')
            ->where('id', $id)
            ->where(function ($q) use ($tenantId) {
                $q->where(fn ($qq) => $qq
                    ->where('tokenable_type', User::class)
                    ->whereIn('tokenable_id', User::withoutGlobalScopes()->where('tenant_id', $tenantId)->pluck('id')))
                ->orWhere(fn ($qq) => $qq
                    ->where('tokenable_type', ClientUser::class)
                    ->whereIn('tokenable_id', ClientUser::withoutGlobalScopes()->where('tenant_id', $tenantId)->pluck('id')));
            })
            ->delete();

        if (!$deleted) {
            return response()->json(['message' => 'Session not found.'], 404);
        }

        return response()->json(['message' => 'Session revoked.']);
    }

    /**
     * Bulk cleanup: revoke every session for accounts that are deactivated,
     * plus (optionally) ones that were never used at all. Never touches a
     * session whose owner is genuinely active.
     */
    public function revokeInactive(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;
        $includeNeverUsed = $request->boolean('include_never_used');

        $staffIds = User::withoutGlobalScopes()->where('tenant_id', $tenantId)->where('is_active', false)->pluck('id');
        $inactiveClientIds = DB::table('clients')->where('tenant_id', $tenantId)->where('status', '!=', 'active')->pluck('id');
        $clientUserIds = ClientUser::withoutGlobalScopes()->where('tenant_id', $tenantId)
            ->where(fn ($q) => $q->where('is_active', false)->orWhereIn('client_id', $inactiveClientIds))
            ->pluck('id');

        $deleted = DB::table('personal_access_tokens')
            ->where(function ($q) use ($staffIds, $clientUserIds) {
                $q->where(fn ($qq) => $qq->where('tokenable_type', User::class)->whereIn('tokenable_id', $staffIds))
                  ->orWhere(fn ($qq) => $qq->where('tokenable_type', ClientUser::class)->whereIn('tokenable_id', $clientUserIds));
            })
            ->delete();

        $deletedNeverUsed = 0;
        if ($includeNeverUsed) {
            $allStaffIds = User::withoutGlobalScopes()->where('tenant_id', $tenantId)->pluck('id');
            $allClientUserIds = ClientUser::withoutGlobalScopes()->where('tenant_id', $tenantId)->pluck('id');
            $deletedNeverUsed = DB::table('personal_access_tokens')
                ->whereNull('last_used_at')
                ->where(function ($q) use ($allStaffIds, $allClientUserIds) {
                    $q->where(fn ($qq) => $qq->where('tokenable_type', User::class)->whereIn('tokenable_id', $allStaffIds))
                      ->orWhere(fn ($qq) => $qq->where('tokenable_type', ClientUser::class)->whereIn('tokenable_id', $allClientUserIds));
                })
                ->delete();
        }

        return response()->json([
            'message' => "Revoked {$deleted} session(s) on deactivated accounts" . ($includeNeverUsed ? " and {$deletedNeverUsed} never-used session(s)." : '.'),
        ]);
    }
}
