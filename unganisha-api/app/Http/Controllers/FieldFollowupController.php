<?php

namespace App\Http\Controllers;

use App\Models\FieldFollowup;
use App\Models\FieldVisit;
use Illuminate\Http\Request;

class FieldFollowupController extends Controller
{
    public function index(FieldVisit $visit)
    {
        return response()->json(
            $visit->followups()->with('user:id,name')->orderByDesc('call_date')->get()
        );
    }

    public function store(Request $request, FieldVisit $visit)
    {
        $data = $request->validate([
            'call_date'          => 'required|date',
            'outcome'            => 'required|in:answered,no_answer,callback,interested,not_interested,converted',
            'notes'              => 'nullable|string',
            'next_followup_date' => 'nullable|date',
        ]);

        $data['visit_id'] = $visit->id;
        $data['user_id']  = auth()->id();

        $followup = FieldFollowup::create($data);

        // Keep the visit's next_followup_date in sync
        if (!empty($data['next_followup_date'])) {
            $visit->update(['next_followup_date' => $data['next_followup_date']]);
        }

        // Auto-update visit status based on outcome
        $statusMap = [
            'interested'     => 'interested',
            'not_interested' => 'not_interested',
            'converted'      => 'converted',
        ];
        if (isset($statusMap[$data['outcome']])) {
            $visit->update(['status' => $statusMap[$data['outcome']]]);
        }

        return response()->json($followup->load('user:id,name'), 201);
    }

    public function destroy(FieldVisit $visit, FieldFollowup $followup)
    {
        $followup->delete();
        return response()->json(null, 204);
    }
}
