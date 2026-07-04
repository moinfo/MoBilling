<?php

namespace App\Http\Controllers\Portal;

use App\Http\Controllers\Controller;
use App\Models\KbArticle;
use App\Models\KbCategory;
use Illuminate\Http\Request;

class PortalKnowledgebaseController extends Controller
{
    public function index(Request $request)
    {
        $tenantId = $request->user()->tenant_id;
        $search   = trim((string) $request->query('search', ''));

        // Categories with their published articles.
        $categories = KbCategory::withoutGlobalScopes()
            ->where('tenant_id', $tenantId)
            ->where('is_active', true)
            ->orderBy('sort_order')
            ->orderBy('name')
            ->with(['articles' => function ($q) use ($tenantId, $search) {
                $q->withoutGlobalScopes()
                    ->where('tenant_id', $tenantId)
                    ->published()
                    ->when($search !== '', fn ($qq) => $qq->where(function ($w) use ($search) {
                        $w->where('title', 'like', "%{$search}%")
                          ->orWhere('body', 'like', "%{$search}%");
                    }))
                    ->orderBy('sort_order')
                    ->orderByDesc('created_at');
            }])
            ->get();

        // Published articles with no category (still browsable).
        $uncategorized = KbArticle::withoutGlobalScopes()
            ->where('tenant_id', $tenantId)
            ->whereNull('kb_category_id')
            ->published()
            ->when($search !== '', fn ($q) => $q->where(function ($w) use ($search) {
                $w->where('title', 'like', "%{$search}%")
                  ->orWhere('body', 'like', "%{$search}%");
            }))
            ->orderBy('sort_order')
            ->orderByDesc('created_at')
            ->get();

        $out = $categories
            ->map(fn ($c) => [
                'id'       => $c->id,
                'name'     => $c->name,
                'slug'     => $c->slug,
                'description' => $c->description,
                'articles' => $c->articles->map(fn ($a) => $this->articleSummary($a))->values(),
            ])
            // When searching, hide categories that matched nothing.
            ->when($search !== '', fn ($col) => $col->filter(fn ($c) => count($c['articles']) > 0)->values());

        if ($uncategorized->isNotEmpty()) {
            $out->push([
                'id'       => null,
                'name'     => 'General',
                'slug'     => 'general',
                'description' => null,
                'articles' => $uncategorized->map(fn ($a) => $this->articleSummary($a))->values(),
            ]);
        }

        return response()->json(['data' => $out->values()]);
    }

    public function show(Request $request, string $slug)
    {
        $tenantId = $request->user()->tenant_id;

        $article = KbArticle::withoutGlobalScopes()
            ->where('tenant_id', $tenantId)
            ->where('slug', $slug)
            ->published()
            ->with('category')
            ->firstOrFail();

        // Increment views without touching updated_at.
        KbArticle::withoutGlobalScopes()->where('id', $article->id)->increment('views');

        return response()->json([
            'data' => [
                'id'            => $article->id,
                'title'         => $article->title,
                'slug'          => $article->slug,
                'body'          => $article->body,
                'views'         => $article->views + 1,
                'category_name' => $article->category?->name,
                'category_slug' => $article->category?->slug,
                'created_at'    => $article->created_at->toISOString(),
                'updated_at'    => $article->updated_at->toISOString(),
            ],
        ]);
    }

    private function articleSummary(KbArticle $a): array
    {
        return [
            'id'    => $a->id,
            'title' => $a->title,
            'slug'  => $a->slug,
            'views' => $a->views,
            'excerpt' => \Illuminate\Support\Str::limit(strip_tags($a->body), 160),
        ];
    }
}
