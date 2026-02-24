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

        // Block access if tenant is deactivated
        if ($user->tenant && !$user->tenant->is_active) {
            return response()->json(['message' => 'Your organization has been deactivated'], 403);
        }

        return $next($request);
    }
}
