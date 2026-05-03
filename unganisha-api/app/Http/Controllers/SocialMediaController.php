<?php

namespace App\Http\Controllers;

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

    const PLATFORMS = ['instagram', 'facebook', 'threads', 'x', 'tiktok'];

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
            'scheduled_date'       => 'required|date',
            'brief'                => 'nullable|string',
            'assigned_designer_id' => 'nullable|uuid|exists:users,id',
            'assigned_creator_id'  => 'nullable|uuid|exists:users,id',
        ]);

        $post = SocialPost::create([...$data, 'created_by' => $request->user()->id]);

        // Seed one platform row per platform
        foreach (self::PLATFORMS as $platform) {
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
            'scheduled_date'       => 'sometimes|date',
            'brief'                => 'nullable|string',
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

        if (!in_array($platform, self::PLATFORMS)) {
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

    // ── Helpers ──────────────────────────────────────────────────

    private function formatPost(SocialPost $post): array
    {
        return [
            'id'                   => $post->id,
            'title'                => $post->title,
            'type'                 => $post->type,
            'scheduled_date'       => $post->scheduled_date?->format('Y-m-d'),
            'brief'                => $post->brief,
            'caption'              => $post->caption,
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
