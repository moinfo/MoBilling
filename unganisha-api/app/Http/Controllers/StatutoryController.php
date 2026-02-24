<?php

namespace App\Http\Controllers;

use App\Http\Requests\StoreStatutoryRequest;
use App\Http\Resources\StatutoryResource;
use App\Models\Statutory;
use Illuminate\Http\Request;

class StatutoryController extends Controller
{
    public function index(Request $request)
    {
        $query = Statutory::with(['billCategory.parent', 'currentBill.payments']);

        if ($request->has('search')) {
            $query->where('name', 'LIKE', "%{$request->search}%");
        }

        return StatutoryResource::collection(
            $query->orderBy('next_due_date')->paginate($request->per_page ?? 20)
        );
    }

    public function store(StoreStatutoryRequest $request)
    {
        $data = $request->validated();

        // Compute next_due_date from issue_date + cycle
        $issueDate = \Carbon\Carbon::parse($data['issue_date']);
        $data['next_due_date'] = Statutory::computeDueDate($issueDate, $data['cycle'])->toDateString();

        $statutory = Statutory::create($data);

        // Auto-generate the first bill
        $statutory->generateBill();

        return new StatutoryResource(
            $statutory->load(['billCategory.parent', 'currentBill.payments'])
        );
    }

    public function show(Statutory $statutory)
    {
        return new StatutoryResource(
            $statutory->load(['billCategory.parent', 'currentBill.payments'])
        );
    }

    public function update(StoreStatutoryRequest $request, Statutory $statutory)
    {
        $data = $request->validated();

        // Recompute next_due_date if issue_date or cycle changed
        if (isset($data['issue_date'])) {
            $issueDate = \Carbon\Carbon::parse($data['issue_date']);
            $data['next_due_date'] = Statutory::computeDueDate($issueDate, $data['cycle'] ?? $statutory->cycle)->toDateString();
        }

        $statutory->update($data);

        return new StatutoryResource(
            $statutory->load(['billCategory.parent', 'currentBill.payments'])
        );
    }

    public function destroy(Statutory $statutory)
    {
        $statutory->delete();
        return response()->json(['message' => 'Statutory obligation deleted']);
    }

    /**
     * Schedule dashboard: stat cards + all active statutories with status.
     */
    public function schedule(Request $request)
    {
        $statutories = Statutory::with(['billCategory.parent', 'currentBill.payments'])
            ->where('is_active', true)
            ->orderBy('next_due_date')
            ->get();

        $stats = [
            'total' => $statutories->count(),
            'overdue' => 0,
            'due_soon' => 0,
            'paid' => 0,
        ];

        $items = $statutories->map(function ($s) use (&$stats) {
            $resource = (new StatutoryResource($s))->resolve();

            match ($resource['status']) {
                'overdue' => $stats['overdue']++,
                'due_soon' => $stats['due_soon']++,
                'paid' => $stats['paid']++,
                default => null,
            };

            return $resource;
        });

        return response()->json([
            'stats' => $stats,
            'data' => $items,
        ]);
    }
}
