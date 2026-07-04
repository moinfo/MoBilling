<?php

namespace App\Http\Controllers;

use App\Models\KbCategory;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class KbCategoryController extends Controller
{
    public function index()
    {
        return response()->json([
            'data' => KbCategory::withCount('articles')
                ->orderBy('sort_order')
                ->orderBy('name')
                ->get()
                ->map(fn ($c) => $this->format($c)),
        ]);
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'name'        => 'required|string|max:255',
            'description' => 'nullable|string|max:5000',
            'sort_order'  => 'integer',
            'is_active'   => 'boolean',
        ]);

        $category = KbCategory::create([
            'name'        => $data['name'],
            'slug'        => $this->uniqueSlug($data['name']),
            'description' => $data['description'] ?? null,
            'sort_order'  => $data['sort_order'] ?? 0,
            'is_active'   => $data['is_active'] ?? true,
        ]);

        return response()->json(['data' => $this->format($category->loadCount('articles'))], 201);
    }

    public function update(Request $request, KbCategory $kbCategory)
    {
        $data = $request->validate([
            'name'        => 'sometimes|string|max:255',
            'description' => 'nullable|string|max:5000',
            'sort_order'  => 'integer',
            'is_active'   => 'boolean',
        ]);

        if (array_key_exists('name', $data) && $data['name'] !== $kbCategory->name) {
            $data['slug'] = $this->uniqueSlug($data['name'], $kbCategory->id);
        }

        $kbCategory->update($data);

        return response()->json(['data' => $this->format($kbCategory->fresh()->loadCount('articles'))]);
    }

    public function destroy(KbCategory $kbCategory)
    {
        $kbCategory->delete();
        return response()->json(null, 204);
    }

    private function uniqueSlug(string $name, ?string $ignoreId = null): string
    {
        $base = Str::slug($name) ?: 'category';
        $slug = $base;
        $i = 2;
        while (KbCategory::withTrashed()
            ->where('slug', $slug)
            ->when($ignoreId, fn ($q) => $q->where('id', '!=', $ignoreId))
            ->exists()) {
            $slug = $base . '-' . $i++;
        }
        return $slug;
    }

    private function format(KbCategory $c): array
    {
        return [
            'id'             => $c->id,
            'name'           => $c->name,
            'slug'           => $c->slug,
            'description'    => $c->description,
            'sort_order'     => $c->sort_order,
            'is_active'      => $c->is_active,
            'articles_count' => $c->articles_count ?? 0,
            'created_at'     => $c->created_at->toISOString(),
        ];
    }
}
