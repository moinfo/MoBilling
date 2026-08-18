<?php

namespace App\Http\Controllers;

use App\Models\Release;

/** Public (no auth) — a self-hosted install's own "Check for Updates" call. Admin CRUD lives in Admin\ReleaseController. */
class ReleaseController extends Controller
{
    public function latest()
    {
        $release = Release::where('is_active', true)->orderByDesc('released_at')->first();

        if (!$release) {
            return response()->json(['data' => null]);
        }

        return response()->json(['data' => [
            'version' => $release->version,
            'changelog' => $release->changelog,
            'download_url' => $release->download_url,
            'released_at' => $release->released_at->toDateString(),
        ]]);
    }
}
