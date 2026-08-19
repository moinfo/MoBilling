<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Release;
use Illuminate\Http\Request;

class ReleaseController extends Controller
{
    private function authorize(): void
    {
        if (!auth()->user()->isSuperAdmin()) {
            abort(403, 'Unauthorized');
        }
    }

    public function index()
    {
        $this->authorize();

        return response()->json(['data' => Release::orderByDesc('released_at')->get()]);
    }

    public function store(Request $request)
    {
        $this->authorize();

        $validated = $request->validate([
            'version' => 'required|string|max:50|unique:releases,version',
            'changelog' => 'nullable|string|max:5000',
            'download_url' => 'nullable|url|max:500',
            'released_at' => 'required|date',
            'is_active' => 'boolean',
        ]);

        $release = Release::create($validated);

        return response()->json(['data' => $release], 201);
    }

    public function update(Request $request, Release $release)
    {
        $this->authorize();

        $validated = $request->validate([
            'version' => 'required|string|max:50|unique:releases,version,' . $release->id,
            'changelog' => 'nullable|string|max:5000',
            'download_url' => 'nullable|url|max:500',
            'released_at' => 'required|date',
            'is_active' => 'boolean',
        ]);

        $release->update($validated);

        return response()->json(['data' => $release]);
    }

    public function destroy(Release $release)
    {
        $this->authorize();

        $release->delete();

        return response()->json(['message' => 'Release deleted.']);
    }
}
