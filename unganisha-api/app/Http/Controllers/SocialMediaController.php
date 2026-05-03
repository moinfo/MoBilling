<?php

namespace App\Http\Controllers;

use App\Models\ClientDesignOrder;
use App\Models\SocialPlatform;
use App\Models\SocialPost;
use App\Models\SocialPostPlatform;
use App\Models\SocialTarget;
use App\Models\User;
use App\Traits\AuthorizesPermissions;
use Carbon\Carbon;
use Illuminate\Http\Request;

class SocialMediaController extends Controller
{
    use AuthorizesPermissions;

    // ── Platform Settings ─────────────────────────────────────────

    public function platformSettings(Request $request)
    {
        $this->authorizePermission('social.read');
        $platforms = SocialPlatform::orderBy('sort_order')->get()
            ->map(fn ($p) => $this->formatPlatform($p));
        return response()->json(['data' => $platforms]);
    }

    public function storePlatform(Request $request)
    {
        $this->authorizePermission('social.targets'); // reuse targets permission for settings

        $data = $request->validate([
            'name'        => 'required|string|max:50|alpha_dash',
            'label'       => 'required|string|max:100',
            'color'       => 'nullable|string|max:50',
            'icon'        => 'nullable|string|max:50',
            'profile_url' => 'nullable|string|max:1000',
            'is_active'   => 'boolean',
            'sort_order'  => 'integer|min:0|max:99',
        ]);

        // Enforce unique name per tenant
        if (SocialPlatform::where('name', $data['name'])->exists()) {
            return response()->json(['message' => 'A platform with this name already exists.'], 422);
        }

        $platform = SocialPlatform::create($data);
        return response()->json(['data' => $this->formatPlatform($platform)], 201);
    }

    public function updatePlatform(Request $request, SocialPlatform $socialPlatform)
    {
        $this->authorizePermission('social.targets');

        $data = $request->validate([
            'label'       => 'sometimes|string|max:100',
            'color'       => 'nullable|string|max:50',
            'icon'        => 'nullable|string|max:50',
            'profile_url' => 'nullable|string|max:1000',
            'is_active'   => 'boolean',
            'sort_order'  => 'integer|min:0|max:99',
        ]);

        $socialPlatform->update($data);
        return response()->json(['data' => $this->formatPlatform($socialPlatform)]);
    }

    public function destroyPlatform(SocialPlatform $socialPlatform)
    {
        $this->authorizePermission('social.targets');
        $socialPlatform->delete();
        return response()->json(['message' => 'Platform removed.']);
    }

    // ── Posts ────────────────────────────────────────────────────

    public function posts(Request $request)
    {
        $this->authorizePermission('social.read');

        $query = SocialPost::with(['platforms', 'designer:id,name', 'creator:id,name'])
            ->orderBy('scheduled_date');

        if ($request->week_start) {
            $start = Carbon::parse($request->week_start)->startOfDay();
            $end   = $start->copy()->addDays(6)->endOfDay();
            $query->whereBetween('scheduled_date', [$start, $end]);
        }

        if ($request->status)  $query->where('status', $request->status);
        if ($request->type)    $query->where('type', $request->type);

        return response()->json(['data' => $query->get()->map(fn ($p) => $this->formatPost($p))]);
    }

    public function storePost(Request $request)
    {
        $this->authorizePermission('social.create');

        $data = $request->validate([
            'title'                => 'required|string|max:255',
            'type'                 => 'required|in:product_education,holiday,employee_birthday,promotion,announcement,general',
            'post_format'          => 'nullable|in:feed_post,reel,story,carousel',
            'media_type'           => 'nullable|in:image,video',
            'scheduled_date'       => 'required|date',
            'scheduled_time'       => 'nullable|date_format:H:i',
            'brief'                => 'nullable|string',
            'hashtags'             => 'nullable|string',
            'assigned_designer_id' => 'nullable|uuid|exists:users,id',
            'assigned_creator_id'  => 'nullable|uuid|exists:users,id',
        ]);

        $post = SocialPost::create([...$data, 'created_by' => $request->user()->id]);

        // Seed one row per active configured platform (dynamic, not hardcoded)
        $activePlatforms = SocialPlatform::active()->pluck('name');
        foreach ($activePlatforms as $platform) {
            SocialPostPlatform::create(['social_post_id' => $post->id, 'platform' => $platform]);
        }

        return response()->json(['data' => $this->formatPost($post->load(['platforms', 'designer:id,name', 'creator:id,name']))], 201);
    }

    public function updatePost(Request $request, SocialPost $socialPost)
    {
        $this->authorizePermission('social.update');

        $data = $request->validate([
            'title'                => 'sometimes|string|max:255',
            'type'                 => 'sometimes|in:product_education,holiday,employee_birthday,promotion,announcement,general',
            'post_format'          => 'sometimes|in:feed_post,reel,story,carousel',
            'media_type'           => 'sometimes|in:image,video',
            'scheduled_date'       => 'sometimes|date',
            'scheduled_time'       => 'nullable|date_format:H:i',
            'brief'                => 'nullable|string',
            'hashtags'             => 'nullable|string',
            'assigned_designer_id' => 'nullable|uuid|exists:users,id',
            'assigned_creator_id'  => 'nullable|uuid|exists:users,id',
        ]);

        $socialPost->update($data);

        return response()->json(['data' => $this->formatPost($socialPost->load(['platforms', 'designer:id,name', 'creator:id,name']))]);
    }

    public function destroyPost(SocialPost $socialPost)
    {
        $this->authorizePermission('social.delete');
        $socialPost->delete();
        return response()->json(['message' => 'Post deleted.']);
    }

    // ── Design status ────────────────────────────────────────────

    public function updateDesign(Request $request, SocialPost $socialPost)
    {
        $this->authorizePermission('social.update');

        $data = $request->validate([
            'design_status'   => 'required|in:pending,in_progress,done',
            'design_notes'    => 'nullable|string',
            'design_file_url' => 'nullable|string|max:1000',
        ]);

        $socialPost->update($data);
        $socialPost->syncStatus();

        return response()->json(['data' => $this->formatPost($socialPost->load(['platforms', 'designer:id,name', 'creator:id,name']))]);
    }

    // ── Caption / content ────────────────────────────────────────

    public function updateContent(Request $request, SocialPost $socialPost)
    {
        $this->authorizePermission('social.update');

        $data = $request->validate([
            'caption'        => 'nullable|string',
            'hashtags'       => 'nullable|string',
            'content_status' => 'required|in:pending,ready',
        ]);

        $socialPost->update($data);
        $socialPost->syncStatus();

        return response()->json(['data' => $this->formatPost($socialPost->load(['platforms', 'designer:id,name', 'creator:id,name']))]);
    }

    // ── Platform posting ─────────────────────────────────────────

    public function togglePlatform(Request $request, SocialPost $socialPost, string $platform)
    {
        $this->authorizePermission('social.update');

        $validPlatforms = SocialPlatform::pluck('name')->toArray();
        if (!in_array($platform, $validPlatforms)) {
            return response()->json(['message' => 'Invalid platform.'], 422);
        }

        $data = $request->validate([
            'posted'   => 'required|boolean',
            'post_url' => 'nullable|string|max:1000',
        ]);

        $row = $socialPost->platforms()->where('platform', $platform)->firstOrFail();
        $row->update([
            'posted'    => $data['posted'],
            'post_url'  => $data['post_url'] ?? $row->post_url,
            'posted_at' => $data['posted'] ? now() : null,
            'posted_by' => $data['posted'] ? $request->user()->id : null,
        ]);

        $socialPost->load('platforms');
        $socialPost->syncStatus();

        return response()->json(['data' => $this->formatPost($socialPost->load(['platforms', 'designer:id,name', 'creator:id,name']))]);
    }

    // ── Targets ──────────────────────────────────────────────────

    public function targets(Request $request)
    {
        $this->authorizePermission('social.read');

        $targets = SocialTarget::with('user:id,name')
            ->get()
            ->map(fn ($t) => $this->formatTarget($t));

        return response()->json(['data' => $targets]);
    }

    public function upsertTarget(Request $request)
    {
        $this->authorizePermission('social.targets');

        $data = $request->validate([
            'user_id'        => 'required|uuid|exists:users,id',
            'metric'         => 'required|in:designs,posts',
            'weekly_target'  => 'required|integer|min:1|max:500',
            'daily_target'   => 'required|integer|min:1|max:100',
            'active_days'    => 'required|array|min:1|max:7',
            'active_days.*'  => 'integer|min:1|max:7',
            'effective_from' => 'required|date',
        ]);

        $target = SocialTarget::updateOrCreate(
            ['tenant_id' => auth()->user()->tenant_id, 'user_id' => $data['user_id'], 'metric' => $data['metric']],
            $data
        );

        return response()->json(['data' => $this->formatTarget($target->load('user:id,name'))]);
    }

    public function destroyTarget(SocialTarget $socialTarget)
    {
        $this->authorizePermission('social.targets');
        $socialTarget->delete();
        return response()->json(['message' => 'Target removed.']);
    }

    // ── Weekly summary (targets vs actual) ───────────────────────

    public function weeklySummary(Request $request)
    {
        $this->authorizePermission('social.read');

        $weekStart = Carbon::parse($request->week_start ?? now()->startOfWeek(Carbon::MONDAY));
        $weekEnd   = $weekStart->copy()->endOfWeek(Carbon::SUNDAY);

        $targets = SocialTarget::with('user:id,name')->get();

        $days = collect(range(0, 6))->map(fn ($i) => $weekStart->copy()->addDays($i));

        $summary = $targets->map(function ($target) use ($weekStart, $weekEnd, $days) {
            // Actual achieved this week
            if ($target->metric === 'designs') {
                $achieved = SocialPost::whereBetween('scheduled_date', [$weekStart, $weekEnd])
                    ->where('design_status', 'done')
                    ->where('assigned_designer_id', $target->user_id)
                    ->count();
            } else {
                // Count platform posts by this user this week
                $achieved = SocialPostPlatform::whereHas('post', fn ($q) =>
                    $q->whereBetween('scheduled_date', [$weekStart, $weekEnd])
                )->where('posted_by', $target->user_id)
                 ->where('posted', true)
                 ->count();
            }

            // Per-day breakdown
            $dailyBreakdown = $days->map(function ($day) use ($target) {
                $isoDay = (int) $day->format('N'); // 1=Mon … 7=Sun
                $isActive = in_array($isoDay, $target->active_days);

                if ($target->metric === 'designs') {
                    $done = SocialPost::whereDate('scheduled_date', $day->toDateString())
                        ->where('design_status', 'done')
                        ->where('assigned_designer_id', $target->user_id)
                        ->count();
                } else {
                    $done = SocialPostPlatform::whereHas('post', fn ($q) =>
                        $q->whereDate('scheduled_date', $day->toDateString())
                    )->where('posted_by', $target->user_id)
                     ->where('posted', true)
                     ->count();
                }

                return [
                    'date'      => $day->toDateString(),
                    'day_name'  => $day->format('D'),
                    'is_active' => $isActive,
                    'target'    => $isActive ? $target->daily_target : 0,
                    'achieved'  => $done,
                    'met'       => !$isActive || $done >= $target->daily_target,
                ];
            });

            return [
                'target'         => $this->formatTarget($target),
                'weekly_achieved' => $achieved,
                'weekly_target'  => $target->weekly_target,
                'percent'        => $target->weekly_target > 0
                    ? min(100, round(($achieved / $target->weekly_target) * 100))
                    : 0,
                'daily'          => $dailyBreakdown->values(),
            ];
        });

        return response()->json([
            'week_start' => $weekStart->toDateString(),
            'week_end'   => $weekEnd->toDateString(),
            'data'       => $summary->values(),
        ]);
    }

    // ── Client Design Orders ─────────────────────────────────────

    public function designOrders(Request $request)
    {
        $this->authorizePermission('social.read');

        $query = ClientDesignOrder::with(['client:id,name', 'designer:id,name'])
            ->orderByRaw("FIELD(status,'pending','in_progress','needs_revision','done','delivered')")
            ->orderBy('due_date');

        if ($request->status)      $query->where('status', $request->status);
        if ($request->design_type) $query->where('design_type', $request->design_type);
        if ($request->designer_id) $query->where('assigned_designer_id', $request->designer_id);

        return response()->json(['data' => $query->get()->map(fn ($o) => $this->formatDesignOrder($o))]);
    }

    public function storeDesignOrder(Request $request)
    {
        $this->authorizePermission('social.create');

        $data = $request->validate([
            'title'               => 'required|string|max:255',
            'client_id'           => 'nullable|uuid|exists:clients,id',
            'design_type'         => 'required|in:logo,flyer,brochure,business_card,banner,book_cover,label_poster,social_media_graphic,merchandise,other',
            'description'         => 'nullable|string',
            'reference_url'       => 'nullable|string|max:1000',
            'assigned_designer_id'=> 'nullable|uuid|exists:users,id',
            'due_date'            => 'nullable|date',
            'price'               => 'nullable|numeric|min:0',
        ]);

        $order = ClientDesignOrder::create([...$data, 'created_by' => $request->user()->id]);

        return response()->json(['data' => $this->formatDesignOrder($order->load(['client:id,name', 'designer:id,name']))], 201);
    }

    public function updateDesignOrder(Request $request, ClientDesignOrder $clientDesignOrder)
    {
        $this->authorizePermission('social.update');

        $data = $request->validate([
            'title'                => 'sometimes|string|max:255',
            'client_id'            => 'nullable|uuid|exists:clients,id',
            'design_type'          => 'sometimes|in:logo,flyer,brochure,business_card,banner,book_cover,label_poster,social_media_graphic,merchandise,other',
            'description'          => 'nullable|string',
            'reference_url'        => 'nullable|string|max:1000',
            'assigned_designer_id' => 'nullable|uuid|exists:users,id',
            'status'               => 'sometimes|in:pending,in_progress,needs_revision,done,delivered',
            'due_date'             => 'nullable|date',
            'file_url'             => 'nullable|string|max:1000',
            'revision_notes'       => 'nullable|string',
            'price'                => 'nullable|numeric|min:0',
        ]);

        // Auto-increment revision_count when status changes to needs_revision
        if (isset($data['status']) && $data['status'] === 'needs_revision'
            && $clientDesignOrder->status !== 'needs_revision') {
            $data['revision_count'] = $clientDesignOrder->revision_count + 1;
        }

        $clientDesignOrder->update($data);

        return response()->json(['data' => $this->formatDesignOrder($clientDesignOrder->load(['client:id,name', 'designer:id,name']))]);
    }

    public function destroyDesignOrder(ClientDesignOrder $clientDesignOrder)
    {
        $this->authorizePermission('social.delete');
        $clientDesignOrder->delete();
        return response()->json(['message' => 'Design order deleted.']);
    }

    // ── Helpers ──────────────────────────────────────────────────

    private function formatPost(SocialPost $post): array
    {
        return [
            'id'                   => $post->id,
            'title'                => $post->title,
            'type'                 => $post->type,
            'post_format'          => $post->post_format ?? 'feed_post',
            'media_type'           => $post->media_type ?? 'image',
            'scheduled_date'       => $post->scheduled_date?->format('Y-m-d'),
            'scheduled_time'       => $post->scheduled_time ? substr($post->scheduled_time, 0, 5) : null,
            'brief'                => $post->brief,
            'caption'              => $post->caption,
            'hashtags'             => $post->hashtags,
            'design_file_url'      => $post->design_file_url,
            'design_notes'         => $post->design_notes,
            'assigned_designer'    => $post->designer ? ['id' => $post->designer->id, 'name' => $post->designer->name] : null,
            'assigned_creator'     => $post->creator  ? ['id' => $post->creator->id,  'name' => $post->creator->name]  : null,
            'design_status'        => $post->design_status,
            'content_status'       => $post->content_status,
            'status'               => $post->status,
            'platforms'            => $post->platforms->map(fn ($p) => [
                'platform'  => $p->platform,
                'posted'    => $p->posted,
                'posted_at' => $p->posted_at?->toDateTimeString(),
                'post_url'  => $p->post_url,
            ])->keyBy('platform'),
            'created_at'           => $post->created_at,
        ];
    }

    private function formatPlatform(SocialPlatform $p): array
    {
        return [
            'id'          => $p->id,
            'name'        => $p->name,
            'label'       => $p->label,
            'color'       => $p->color,
            'icon'        => $p->icon,
            'profile_url' => $p->profile_url,
            'is_active'   => $p->is_active,
            'sort_order'  => $p->sort_order,
        ];
    }

    private function formatDesignOrder(ClientDesignOrder $o): array
    {
        $isOverdue = $o->due_date && $o->due_date->isPast() && !in_array($o->status, ['done', 'delivered']);
        return [
            'id'                   => $o->id,
            'title'                => $o->title,
            'design_type'          => $o->design_type,
            'description'          => $o->description,
            'reference_url'        => $o->reference_url,
            'client'               => $o->client ? ['id' => $o->client->id, 'name' => $o->client->name] : null,
            'designer'             => $o->designer ? ['id' => $o->designer->id, 'name' => $o->designer->name] : null,
            'status'               => $o->status,
            'due_date'             => $o->due_date?->format('Y-m-d'),
            'is_overdue'           => $isOverdue,
            'file_url'             => $o->file_url,
            'revision_count'       => $o->revision_count,
            'revision_notes'       => $o->revision_notes,
            'price'                => $o->price,
            'created_at'           => $o->created_at,
        ];
    }

    private function formatTarget(SocialTarget $t): array
    {
        return [
            'id'             => $t->id,
            'user'           => $t->user ? ['id' => $t->user->id, 'name' => $t->user->name] : null,
            'metric'         => $t->metric,
            'weekly_target'  => $t->weekly_target,
            'daily_target'   => $t->daily_target,
            'active_days'    => $t->active_days,
            'effective_from' => $t->effective_from?->format('Y-m-d'),
        ];
    }
}
