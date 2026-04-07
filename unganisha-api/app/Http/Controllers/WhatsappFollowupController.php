<?php

namespace App\Http\Controllers;

use App\Models\WhatsappContact;
use App\Models\WhatsappFollowup;
use Illuminate\Http\Request;

class WhatsappFollowupController extends Controller
{
    public function index(WhatsappContact $whatsappContact)
    {
        return response()->json(
            $whatsappContact->followups()->with('user:id,name')->get()
        );
    }

    public function store(Request $request, WhatsappContact $whatsappContact)
    {
        $data = $request->validate([
            'call_date'          => 'required|date',
            'outcome'            => 'required|in:answered,no_answer,callback,interested,not_interested,converted',
            'notes'              => 'nullable|string',
            'next_followup_date' => 'nullable|date',
        ]);

        $data['whatsapp_contact_id'] = $whatsappContact->id;
        $data['user_id'] = auth()->id();

        $followup = WhatsappFollowup::create($data);

        // Update contact's next follow-up date if provided
        if (!empty($data['next_followup_date'])) {
            $whatsappContact->update(['next_followup_date' => $data['next_followup_date']]);
        }

        return response()->json($followup->load('user:id,name'), 201);
    }

    public function destroy(WhatsappContact $whatsappContact, WhatsappFollowup $followup)
    {
        $followup->delete();
        return response()->json(null, 204);
    }
}
