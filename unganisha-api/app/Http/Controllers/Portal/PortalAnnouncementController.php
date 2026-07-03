<?php

namespace App\Http\Controllers\Portal;

use App\Http\Controllers\Controller;
use App\Models\Announcement;
use Illuminate\Http\Request;

class PortalAnnouncementController extends Controller
{
    public function index(Request $request)
    {
        $items = Announcement::withoutGlobalScopes()
            ->where('tenant_id', $request->user()->tenant_id)
            ->published()
            ->orderByDesc('published_at')
            ->limit(50)
            ->get()
            ->map(fn ($a) => [
                'id'           => $a->id,
                'title'        => $a->title,
                'body'         => $a->body,
                'published_at' => $a->published_at->toISOString(),
            ]);

        return response()->json(['data' => $items]);
    }
}
