<?php

namespace App\Http\Controllers;

use App\Models\Announcement;
use Illuminate\Http\Request;

class AnnouncementController extends Controller
{
    public function index()
    {
        return response()->json([
            'data' => Announcement::orderByDesc('created_at')->get()->map(fn ($a) => $this->format($a)),
        ]);
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'title'        => 'required|string|max:255',
            'body'         => 'required|string|max:20000',
            'is_published' => 'boolean',
        ]);

        $announcement = Announcement::create([
            'title'        => $data['title'],
            'body'         => $data['body'],
            'is_published' => $data['is_published'] ?? false,
            'published_at' => ($data['is_published'] ?? false) ? now() : null,
            'created_by'   => auth()->id(),
        ]);

        return response()->json(['data' => $this->format($announcement)], 201);
    }

    public function update(Request $request, Announcement $announcement)
    {
        $data = $request->validate([
            'title'        => 'sometimes|string|max:255',
            'body'         => 'sometimes|string|max:20000',
            'is_published' => 'boolean',
        ]);

        if (array_key_exists('is_published', $data)) {
            // stamp first publication; keep the original date on re-publish
            if ($data['is_published'] && !$announcement->published_at) {
                $data['published_at'] = now();
            }
        }

        $announcement->update($data);

        return response()->json(['data' => $this->format($announcement->fresh())]);
    }

    public function destroy(Announcement $announcement)
    {
        $announcement->delete();
        return response()->json(null, 204);
    }

    private function format(Announcement $a): array
    {
        return [
            'id'           => $a->id,
            'title'        => $a->title,
            'body'         => $a->body,
            'is_published' => $a->is_published,
            'published_at' => $a->published_at?->toISOString(),
            'created_at'   => $a->created_at->toISOString(),
        ];
    }
}
