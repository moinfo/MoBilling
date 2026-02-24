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

        if (!$user->tenant_id) {
            return response()->json(['message' => 'Tenant not found'], 403);
        }

        $tenant = $user->tenant;

        // Block access if tenant is admin-deactivated
        if (!$tenant->is_active) {
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
