<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Route-level guard for the platform /admin/* area. Every admin controller
 * already checks isSuperAdmin() internally; this adds a belt-and-suspenders
 * layer so a newly-added admin route/method can never be reachable by a
 * non-super-admin even if its author forgets the in-controller check.
 */
class EnsureSuperAdmin
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();
        if (!$user || !$user->isSuperAdmin()) {
            abort(403, 'Super administrator access required.');
        }

        return $next($request);
    }
}
