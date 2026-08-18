<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class TenantMiddleware
{
    public function handle(Request $request, Closure $next): Response
    {
        if (!auth()->check()) {
            return response()->json(['message' => 'Unauthenticated'], 401);
        }

        $user = auth()->user();

        // Super admins bypass tenant check (they have no tenant)
        if ($user->isSuperAdmin()) {
            return $next($request);
        }

        // Sanctum tokens never expire (config/sanctum.php) — deactivating a
        // user only blocks future *logins* unless it's also enforced here,
        // on every request, against their still-valid existing token.
        if (!$user->is_active) {
            return response()->json(['message' => 'Your account has been deactivated.'], 403);
        }

        if (!$user->tenant_id) {
            return response()->json(['message' => 'Tenant not found'], 403);
        }

        $tenant = $user->tenant;

        // Block access if tenant is deactivated — a self-hosted install
        // deactivated by license:check gets a distinct code so the
        // frontend can show a license-specific screen (with a path to
        // /license-status, itself deliberately outside this middleware)
        // instead of the generic "deactivated by an admin" message, which
        // would be actively misleading here.
        if (!$tenant->is_active) {
            if ($tenant->is_self_hosted) {
                return response()->json([
                    'message' => 'This install\'s license is inactive.',
                    'code' => 'LICENSE_INACTIVE',
                ], 403);
            }
            return response()->json(['message' => 'Your organization has been deactivated.'], 403);
        }

        // Block access if subscription/trial expired (402 Payment Required)
        if (!$tenant->hasAccess()) {
            return response()->json([
                'message' => 'Your subscription has expired. Please renew to continue.',
                'code' => 'SUBSCRIPTION_EXPIRED',
                'subscription_status' => $tenant->subscriptionStatus(),
            ], 402);
        }

        return $next($request);
    }
}
