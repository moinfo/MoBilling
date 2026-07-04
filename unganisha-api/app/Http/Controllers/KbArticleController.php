<?php

namespace App\Http\Controllers;

use App\Models\KbArticle;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class KbArticleController extends Controller
{
    public function index(Request $request)
    {
        $query = KbArticle::with('category')
            ->orderBy('sort_order')
            ->orderByDesc('created_at');

        if ($request->filled('category_id')) {
            $query->where('kb_category_id', $request->query('category_id'));
        }

        return response()->json([
            'data' => $query->get()->map(fn ($a) => $this->format($a)),
        ]);
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'kb_category_id' => 'nullable|uuid|exists:kb_categories,id',
            'title'          => 'required|string|max:255',
            'body'           => 'required|string',
            'is_published'   => 'boolean',
            'sort_order'     => 'integer',
        ]);

        $article = KbArticle::create([
            'kb_category_id' => $data['kb_category_id'] ?? null,
            'title'          => $data['title'],
            'slug'           => $this->uniqueSlug($data['title']),
            'body'           => $data['body'],
            'is_published'   => $data['is_published'] ?? false,
            'sort_order'     => $data['sort_order'] ?? 0,
        ]);

        return response()->json(['data' => $this->format($article->load('category'))], 201);
    }

    public function update(Request $request, KbArticle $kbArticle)
    {
        $data = $request->validate([
            'kb_category_id' => 'nullable|uuid|exists:kb_categories,id',
            'title'          => 'sometimes|string|max:255',
            'body'           => 'sometimes|string',
            'is_published'   => 'boolean',
            'sort_order'     => 'integer',
        ]);

        if (array_key_exists('title', $data) && $data['title'] !== $kbArticle->title) {
            $data['slug'] = $this->uniqueSlug($data['title'], $kbArticle->id);
        }

        $kbArticle->update($data);

        return response()->json(['data' => $this->format($kbArticle->fresh()->load('category'))]);
    }

    public function destroy(KbArticle $kbArticle)
    {
        $kbArticle->delete();
        return response()->json(null, 204);
    }

    private function uniqueSlug(string $title, ?string $ignoreId = null): string
    {
        $base = Str::slug($title) ?: 'article';
        $slug = $base;
        $i = 2;
        while (KbArticle::withTrashed()
            ->where('slug', $slug)
            ->when($ignoreId, fn ($q) => $q->where('id', '!=', $ignoreId))
            ->exists()) {
            $slug = $base . '-' . $i++;
        }
        return $slug;
    }

    private function format(KbArticle $a): array
    {
        return [
            'id'             => $a->id,
            'kb_category_id' => $a->kb_category_id,
            'category_name'  => $a->category?->name,
            'title'          => $a->title,
            'slug'           => $a->slug,
            'body'           => $a->body,
            'is_published'   => $a->is_published,
            'views'          => $a->views,
            'sort_order'     => $a->sort_order,
            'created_at'     => $a->created_at->toISOString(),
        ];
    }
}
