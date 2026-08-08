<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Symfony\Component\HttpFoundation\Response;

/**
 * Server-side backstop for the 15-minute idle logout: kills a token's
 * session if no authenticated request has come through in that window.
 *
 * This is deliberately independent of Sanctum's own `last_used_at` — that
 * field gets overwritten to "now" by Sanctum's own guard BEFORE this
 * middleware runs (same request, same object), so it can never show a
 * meaningful gap. We track "last seen" ourselves via cache instead.
 *
 * This is a backstop, not the primary UX — the frontend's own idle timer
 * (real mouse/keyboard/touch activity) is what actually logs an inactive
 * user out while they're sitting on the page. This middleware only matters
 * for requests that bypass that (e.g. a leaked token used directly via the
 * API, not through the browser).
 */
class IdleTimeout
{
    private const MINUTES = 15;

    public function handle(Request $request, Closure $next): Response
    {
        $token = $request->user()?->currentAccessToken();

        if ($token && isset($token->id)) {
            $key = "session_idle:{$token->id}";
            $lastSeen = Cache::get($key);

            if ($lastSeen && now()->diffInMinutes($lastSeen, absolute: true) >= self::MINUTES) {
                $token->delete();
                Cache::forget($key);

                return response()->json([
                    'message' => 'Your session expired due to inactivity — please sign in again.',
                    'code'    => 'SESSION_IDLE_TIMEOUT',
                ], 401);
            }

            // TTL well past the threshold so the marker survives long enough
            // for the check above to ever see a genuine 15-minute gap.
            Cache::put($key, now(), now()->addHour());
        }

        return $next($request);
    }
}
