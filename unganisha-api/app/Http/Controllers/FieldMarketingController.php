<?php

namespace App\Http\Controllers;

use App\Models\Client;
use App\Models\FieldSession;
use App\Models\FieldTarget;
use App\Models\FieldVisit;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Http\Request;

class FieldMarketingController extends Controller
{
    // ── Sessions ────────────────────────────────────────────────

    public function sessions(Request $request)
    {
        $query = FieldSession::with(['officer:id,name', 'visits'])
            ->latest('visit_date');

        if ($request->officer_id) $query->where('officer_id', $request->officer_id);
        if ($request->month)      $query->whereMonth('visit_date', $request->month);
        if ($request->year)       $query->whereYear('visit_date', $request->year);

        return response()->json($query->get()->map(fn ($s) => [
            'id'              => $s->id,
            'officer'         => $s->officer,
            'visit_date'      => $s->visit_date->format('Y-m-d'),
            'area'            => $s->area,
            'summary'         => $s->summary,
            'challenges'      => $s->challenges,
            'recommendations' => $s->recommendations,
            'visits_count'    => $s->visits->count(),
            'interested_count'=> $s->visits->whereIn('status', ['interested', 'follow_up', 'converted'])->count(),
            'converted_count' => $s->visits->where('status', 'converted')->count(),
            'created_at'      => $s->created_at,
        ]));
    }

    public function storeSession(Request $request)
    {
        $data = $request->validate([
            'officer_id'      => 'required|uuid|exists:users,id',
            'visit_date'      => 'required|date',
            'area'            => 'required|string|max:255',
            'summary'         => 'nullable|string',
            'challenges'      => 'nullable|string',
            'recommendations' => 'nullable|string',
        ]);

        $session = FieldSession::create($data);
        return response()->json($session->load('officer:id,name'), 201);
    }

    public function updateSession(Request $request, FieldSession $fieldSession)
    {
        $data = $request->validate([
            'officer_id'      => 'sometimes|uuid|exists:users,id',
            'visit_date'      => 'sometimes|date',
            'area'            => 'sometimes|string|max:255',
            'summary'         => 'nullable|string',
            'challenges'      => 'nullable|string',
            'recommendations' => 'nullable|string',
        ]);

        $fieldSession->update($data);
        return response()->json($fieldSession->load('officer:id,name'));
    }

    public function destroySession(FieldSession $fieldSession)
    {
        $fieldSession->delete();
        return response()->json(null, 204);
    }

    // Session detail with all visits
    public function sessionDetail(FieldSession $fieldSession)
    {
        return response()->json([
            'session' => $fieldSession->load(['officer:id,name']),
            'visits'  => $fieldSession->visits()->with('client:id,name')->get(),
        ]);
    }

    // ── Visits ──────────────────────────────────────────────────

    public function storeVisit(Request $request, FieldSession $fieldSession)
    {
        $data = $request->validate([
            'business_name' => 'required|string|max:255',
            'location'      => 'required|string|max:255',
            'phone'         => 'nullable|string|max:50',
            'services'      => 'required|array|min:1',
            'services.*'    => 'string',
            'feedback'      => 'nullable|string',
            'status'        => 'required|in:interested,not_interested,follow_up,converted',
        ]);

        $data['session_id'] = $fieldSession->id;
        $data['officer_id'] = $fieldSession->officer_id;

        $visit = FieldVisit::create($data);
        return response()->json($visit, 201);
    }

    public function updateVisit(Request $request, FieldSession $fieldSession, FieldVisit $visit)
    {
        $data = $request->validate([
            'business_name' => 'sometimes|string|max:255',
            'location'      => 'sometimes|string|max:255',
            'phone'         => 'nullable|string|max:50',
            'services'      => 'sometimes|array|min:1',
            'services.*'    => 'string',
            'feedback'      => 'nullable|string',
            'status'        => 'sometimes|in:interested,not_interested,follow_up,converted',
            'client_id'     => 'nullable|uuid|exists:clients,id',
        ]);

        $visit->update($data);
        return response()->json($visit->load('client:id,name'));
    }

    public function destroyVisit(FieldSession $fieldSession, FieldVisit $visit)
    {
        $visit->delete();
        return response()->json(null, 204);
    }

    public function convertVisit(Request $request, FieldSession $fieldSession, FieldVisit $visit)
    {
        $data = $request->validate([
            'client_id'    => 'nullable|uuid|exists:clients,id',
            'client_name'  => 'required_without:client_id|string|max:255',
            'client_email' => 'nullable|email',
            'client_phone' => 'nullable|string|max:50',
        ]);

        if (!empty($data['client_id'])) {
            $clientId = $data['client_id'];
        } else {
            $client = Client::create([
                'name'  => $data['client_name'],
                'email' => $data['client_email'] ?? null,
                'phone' => $data['client_phone'] ?? $visit->phone,
            ]);
            $clientId = $client->id;
        }

        $visit->update(['client_id' => $clientId, 'status' => 'converted']);
        return response()->json($visit->load('client:id,name'));
    }

    // ── Targets ─────────────────────────────────────────────────

    public function targets(Request $request)
    {
        $month = (int) $request->query('month', now()->month);
        $year  = (int) $request->query('year', now()->year);

        $targets = FieldTarget::with('officer:id,name')
            ->where('month', $month)
            ->where('year', $year)
            ->get();

        // For each officer with a target, compute actual clients won
        $result = $targets->map(function ($t) use ($month, $year) {
            $won = FieldVisit::where('officer_id', $t->officer_id)
                ->whereNotNull('client_id')
                ->whereHas('session', fn ($q) => $q->whereMonth('visit_date', $month)->whereYear('visit_date', $year))
                ->count();

            $visits = FieldVisit::where('officer_id', $t->officer_id)
                ->whereHas('session', fn ($q) => $q->whereMonth('visit_date', $month)->whereYear('visit_date', $year))
                ->count();

            return [
                'id'             => $t->id,
                'officer'        => $t->officer,
                'month'          => $t->month,
                'year'           => $t->year,
                'target_clients' => $t->target_clients,
                'won_clients'    => $won,
                'total_visits'   => $visits,
                'progress'       => $t->target_clients > 0 ? round(($won / $t->target_clients) * 100) : 0,
            ];
        });

        return response()->json($result);
    }

    public function setTarget(Request $request)
    {
        $data = $request->validate([
            'officer_id'     => 'required|uuid|exists:users,id',
            'month'          => 'required|integer|min:1|max:12',
            'year'           => 'required|integer|min:2020',
            'target_clients' => 'required|integer|min:1',
        ]);

        $target = FieldTarget::updateOrCreate(
            ['officer_id' => $data['officer_id'], 'month' => $data['month'], 'year' => $data['year']],
            ['target_clients' => $data['target_clients']]
        );

        return response()->json($target->load('officer:id,name'));
    }

    // ── Stats ────────────────────────────────────────────────────

    public function stats(Request $request)
    {
        $month = (int) $request->query('month', now()->month);
        $year  = (int) $request->query('year', now()->year);

        $visits = FieldVisit::whereHas('session',
            fn ($q) => $q->whereMonth('visit_date', $month)->whereYear('visit_date', $year)
        );

        $byStatus = (clone $visits)->selectRaw('status, COUNT(*) as count')
            ->groupBy('status')->pluck('count', 'status');

        $byOfficer = (clone $visits)->selectRaw('officer_id, COUNT(*) as visits, SUM(client_id IS NOT NULL) as won')
            ->groupBy('officer_id')->get()
            ->map(fn ($r) => [
                'officer_id' => $r->officer_id,
                'visits'     => (int) $r->visits,
                'won'        => (int) $r->won,
                'officer'    => User::find($r->officer_id, ['id', 'name']),
            ]);

        return response()->json([
            'total_visits'    => (clone $visits)->count(),
            'total_converted' => (clone $visits)->whereNotNull('client_id')->count(),
            'by_status'       => $byStatus,
            'by_officer'      => $byOfficer,
        ]);
    }
}
