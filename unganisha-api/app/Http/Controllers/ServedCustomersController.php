<?php

namespace App\Http\Controllers;

use App\Models\ServedCustomer;
use App\Models\ServedCustomerFeedback;
use App\Models\ServedService;
use App\Models\ServedTarget;
use App\Traits\AuthorizesPermissions;
use Carbon\Carbon;
use Carbon\CarbonPeriod;
use Illuminate\Http\Request;

class ServedCustomersController extends Controller
{
    use AuthorizesPermissions;

    // ── Services ─────────────────────────────────────────────────

    public function services()
    {
        $this->authorizePermission('served.read');
        return response()->json([
            'data' => ServedService::orderBy('sort_order')->orderBy('name')->get(),
        ]);
    }

    public function storeService(Request $request)
    {
        $this->authorizePermission('served.settings');
        $data = $request->validate([
            'name'        => 'required|string|max:255',
            'description' => 'nullable|string|max:500',
            'is_active'   => 'boolean',
            'sort_order'  => 'integer|min:0|max:99',
        ]);
        return response()->json(['data' => ServedService::create($data)], 201);
    }

    public function updateService(Request $request, ServedService $servedService)
    {
        $this->authorizePermission('served.settings');
        $data = $request->validate([
            'name'        => 'sometimes|string|max:255',
            'description' => 'nullable|string|max:500',
            'is_active'   => 'boolean',
            'sort_order'  => 'integer|min:0|max:99',
        ]);
        $servedService->update($data);
        return response()->json(['data' => $servedService]);
    }

    public function destroyService(ServedService $servedService)
    {
        $this->authorizePermission('served.settings');
        $servedService->delete();
        return response()->json(null, 204);
    }

    // ── Customers ─────────────────────────────────────────────────

    public function customers(Request $request)
    {
        $this->authorizePermission('served.read');

        $query = ServedCustomer::with(['services', 'feedbacks.createdBy', 'createdBy'])
            ->orderBy('served_date', 'desc')
            ->orderBy('created_at', 'desc');

        if ($request->date) {
            $query->whereDate('served_date', $request->date);
        }
        if ($request->search) {
            $query->where(fn ($q) =>
                $q->where('name', 'like', "%{$request->search}%")
                  ->orWhere('phone', 'like', "%{$request->search}%")
            );
        }

        return response()->json(['data' => $query->get()->map(fn ($c) => $this->format($c))]);
    }

    public function storeCustomer(Request $request)
    {
        $this->authorizePermission('served.create');
        $data = $request->validate([
            'name'          => 'required|string|max:255',
            'phone'         => 'nullable|string|max:30',
            'served_date'   => 'required|date',
            'notes'         => 'nullable|string|max:1000',
            'service_ids'   => 'array',
            'service_ids.*' => 'uuid|exists:served_services,id',
        ]);

        if (!empty($data['phone'])) {
            $data['phone'] = $this->normalizePhone($data['phone']);
        }

        // Duplicate check: same name OR same phone on the same date
        $duplicate = ServedCustomer::where('served_date', $data['served_date'])
            ->where(function ($q) use ($data) {
                $q->whereRaw('LOWER(name) = ?', [strtolower($data['name'])]);
                if (!empty($data['phone'])) {
                    $q->orWhere('phone', $data['phone']);
                }
            })
            ->first();

        if ($duplicate) {
            $reason = strtolower($duplicate->name) === strtolower($data['name'])
                ? 'name'
                : 'phone number';
            return response()->json([
                'message' => "A customer with the same {$reason} was already recorded for this date.",
                'errors'  => ['duplicate' => ["Duplicate: {$duplicate->name} ({$duplicate->phone}) already recorded on this date."]],
            ], 422);
        }

        $data['created_by_user_id'] = auth()->id();

        $customer = ServedCustomer::create($data);
        if (!empty($data['service_ids'])) {
            $customer->services()->sync($data['service_ids']);
        }

        return response()->json(['data' => $this->format($customer->load(['services', 'feedbacks.createdBy', 'createdBy']))], 201);
    }

    public function updateCustomer(Request $request, ServedCustomer $servedCustomer)
    {
        $this->authorizePermission('served.update');
        $data = $request->validate([
            'name'        => 'sometimes|string|max:255',
            'phone'       => 'nullable|string|max:30',
            'served_date' => 'sometimes|date',
            'notes'       => 'nullable|string|max:1000',
            'service_ids' => 'array',
            'service_ids.*' => 'uuid|exists:served_services,id',
        ]);

        if (isset($data['phone'])) {
            $data['phone'] = $this->normalizePhone($data['phone']);
        }

        $servedCustomer->update($data);
        if (array_key_exists('service_ids', $data)) {
            $servedCustomer->services()->sync($data['service_ids'] ?? []);
        }

        return response()->json(['data' => $this->format($servedCustomer->load(['services', 'feedbacks.createdBy', 'createdBy']))]);
    }

    public function destroyCustomer(ServedCustomer $servedCustomer)
    {
        $this->authorizePermission('served.delete');
        $servedCustomer->delete();
        return response()->json(null, 204);
    }

    // ── Feedback ──────────────────────────────────────────────────

    public function storeFeedback(Request $request, ServedCustomer $servedCustomer)
    {
        $this->authorizePermission('served.create');
        $data = $request->validate([
            'rating'         => 'nullable|integer|min:1|max:5',
            'outcome'        => 'nullable|in:satisfied,neutral,dissatisfied',
            'feedback'       => 'nullable|string|max:2000',
            'challenges'     => 'nullable|string|max:2000',
            'internal_notes' => 'nullable|string|max:2000',
        ]);

        $data['called_at']         = now();
        $data['created_by_user_id'] = auth()->id();
        $fb = $servedCustomer->feedbacks()->create($data);
        $fb->load('createdBy');
        return response()->json(['data' => $this->formatFeedback($fb)], 201);
    }

    public function destroyFeedback(ServedCustomer $servedCustomer, ServedCustomerFeedback $feedback)
    {
        $this->authorizePermission('served.delete');
        $feedback->delete();
        return response()->json(null, 204);
    }

    // ── Targets ───────────────────────────────────────────────────

    public function target()
    {
        $this->authorizePermission('served.read');
        $target = ServedTarget::first();
        return response()->json(['data' => $target ? $this->formatTarget($target) : null]);
    }

    public function upsertTarget(Request $request)
    {
        $this->authorizePermission('served.settings');
        $data = $request->validate([
            'new_customers_target'    => 'required|integer|min:1|max:999',
            'called_customers_target' => 'required|integer|min:1|max:999',
            'active_days'             => 'required|array|min:1',
            'active_days.*'           => 'integer|between:1,7',
            'effective_from'          => 'required|date',
        ]);

        $target = ServedTarget::first();
        if ($target) {
            $target->update($data);
        } else {
            $target = ServedTarget::create($data);
        }

        return response()->json(['data' => $this->formatTarget($target)]);
    }

    public function weeklyTargetSummary(Request $request)
    {
        $this->authorizePermission('served.read');

        $weekStart = Carbon::parse($request->input('week_start', now()->startOfWeek(Carbon::MONDAY)))->startOfDay();
        $weekEnd   = $weekStart->copy()->addDays(6)->endOfDay();

        $target = ServedTarget::first();

        // Count new customers per day this week
        $newPerDay = ServedCustomer::selectRaw('DATE(served_date) as day, COUNT(*) as count')
            ->whereBetween('served_date', [$weekStart, $weekEnd])
            ->groupBy('day')
            ->pluck('count', 'day');

        // Count feedback calls per day this week
        $calledPerDay = ServedCustomerFeedback::selectRaw('DATE(called_at) as day, COUNT(*) as count')
            ->whereBetween('called_at', [$weekStart, $weekEnd])
            ->groupBy('day')
            ->pluck('count', 'day');

        $daily = [];
        foreach (CarbonPeriod::create($weekStart, $weekEnd) as $date) {
            $dateStr  = $date->format('Y-m-d');
            $isoDay   = (int) $date->isoWeekday();
            $isActive = $target ? in_array($isoDay, $target->active_days) : true;
            $daily[]  = [
                'date'        => $dateStr,
                'day_name'    => $date->format('D'),
                'is_active'   => $isActive,
                'new_customers' => (int) ($newPerDay[$dateStr] ?? 0),
                'calls_made'    => (int) ($calledPerDay[$dateStr] ?? 0),
            ];
        }

        $totalNew    = array_sum(array_column($daily, 'new_customers'));
        $totalCalled = array_sum(array_column($daily, 'calls_made'));
        $activeDays  = count(array_filter($daily, fn ($d) => $d['is_active']));

        return response()->json([
            'week_start'             => $weekStart->toDateString(),
            'week_end'               => $weekEnd->toDateString(),
            'target'                 => $target ? $this->formatTarget($target) : null,
            'new_customers_achieved' => $totalNew,
            'calls_achieved'         => $totalCalled,
            'new_customers_target'   => $target ? $target->new_customers_target * $activeDays : null,
            'calls_target'           => $target ? $target->called_customers_target * $activeDays : null,
            'daily'                  => $daily,
        ]);
    }

    public function report(Request $request)
    {
        $this->authorizePermission('served.read');

        $start = Carbon::parse($request->input('start_date', now()->startOfMonth()))->startOfDay();
        $end   = Carbon::parse($request->input('end_date',   now()->endOfMonth()))->endOfDay();

        $target = ServedTarget::first();

        $newPerDay = ServedCustomer::selectRaw('DATE(served_date) as day, COUNT(*) as count')
            ->whereBetween('served_date', [$start, $end])
            ->groupBy('day')
            ->pluck('count', 'day');

        $calledPerDay = ServedCustomerFeedback::selectRaw('DATE(called_at) as day, COUNT(*) as count')
            ->whereBetween('called_at', [$start, $end])
            ->groupBy('day')
            ->pluck('count', 'day');

        $daily = [];
        foreach (CarbonPeriod::create($start->toDateString(), $end->toDateString()) as $date) {
            $dateStr  = $date->format('Y-m-d');
            $isoDay   = (int) $date->isoWeekday();
            $isActive = $target ? in_array($isoDay, $target->active_days) : true;
            $newTarget    = ($isActive && $target) ? $target->new_customers_target    : 0;
            $calledTarget = ($isActive && $target) ? $target->called_customers_target : 0;
            $newActual    = (int) ($newPerDay[$dateStr]    ?? 0);
            $calledActual = (int) ($calledPerDay[$dateStr] ?? 0);

            $daily[] = [
                'date'               => $dateStr,
                'day_name'           => $date->format('D'),
                'week'               => $date->isoWeek(),
                'is_active'          => $isActive,
                'new_customers'      => $newActual,
                'new_target'         => $newTarget,
                'new_pct'            => $newTarget > 0 ? round($newActual / $newTarget * 100) : null,
                'calls_made'         => $calledActual,
                'calls_target'       => $calledTarget,
                'calls_pct'          => $calledTarget > 0 ? round($calledActual / $calledTarget * 100) : null,
            ];
        }

        $activeDays       = collect($daily)->where('is_active', true)->count();
        $totalNewTarget   = $target ? $target->new_customers_target    * $activeDays : 0;
        $totalCallTarget  = $target ? $target->called_customers_target * $activeDays : 0;
        $totalNew         = (int) $newPerDay->sum();
        $totalCalled      = (int) $calledPerDay->sum();

        return response()->json([
            'start_date'             => $start->toDateString(),
            'end_date'               => $end->toDateString(),
            'target'                 => $target ? $this->formatTarget($target) : null,
            'new_customers_achieved' => $totalNew,
            'new_customers_target'   => $totalNewTarget,
            'calls_achieved'         => $totalCalled,
            'calls_target'           => $totalCallTarget,
            'daily'                  => $daily,
        ]);
    }

    private function formatTarget(ServedTarget $t): array
    {
        return [
            'id'                      => $t->id,
            'new_customers_target'    => $t->new_customers_target,
            'called_customers_target' => $t->called_customers_target,
            'active_days'             => $t->active_days,
            'effective_from'          => $t->effective_from->toDateString(),
        ];
    }

    private function normalizePhone(?string $phone): ?string
    {
        if (!$phone) return null;
        $digits = preg_replace('/\D/', '', $phone);
        // Strip Tanzania (+255) or Kenya (+254) country code → local 0XXXXXXXXX
        if (preg_match('/^(255|254)(\d{9})$/', $digits, $m)) {
            return '0' . $m[2];
        }
        return $digits ?: null;
    }

    private function format(ServedCustomer $c): array
    {
        return [
            'id'          => $c->id,
            'name'        => $c->name,
            'phone'       => $c->phone,
            'served_date' => $c->served_date->toDateString(),
            'notes'       => $c->notes,
            'services'    => $c->services->map(fn ($s) => ['id' => $s->id, 'name' => $s->name])->values(),
            'feedbacks'   => $c->feedbacks->map(fn ($f) => $this->formatFeedback($f))->values(),
            'created_at'  => $c->created_at->toISOString(),
            'created_by'  => $c->createdBy ? ['id' => $c->createdBy->id, 'name' => $c->createdBy->name] : null,
        ];
    }

    private function formatFeedback(ServedCustomerFeedback $f): array
    {
        return [
            'id'             => $f->id,
            'called_at'      => $f->called_at?->toISOString() ?? now()->toISOString(),
            'rating'         => $f->rating,
            'outcome'        => $f->outcome,
            'feedback'       => $f->feedback,
            'challenges'     => $f->challenges,
            'internal_notes' => $f->internal_notes,
            'created_by'     => $f->createdBy ? ['id' => $f->createdBy->id, 'name' => $f->createdBy->name] : null,
        ];
    }
}
