<?php

namespace App\Http\Controllers;

use App\Models\WhatsappCampaign;
use Illuminate\Http\Request;

class WhatsappCampaignController extends Controller
{
    public function index()
    {
        $campaigns = WhatsappCampaign::withCount([
            'contacts as leads_count',
            'contacts as converted_count' => fn ($q) => $q->whereNotNull('client_id'),
        ])->latest('start_date')->get();

        return response()->json($campaigns);
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'name'       => 'required|string|max:255',
            'start_date' => 'required|date',
            'end_date'   => 'nullable|date|after_or_equal:start_date',
            'budget'     => 'required|numeric|min:0',
            'notes'      => 'nullable|string',
        ]);

        $campaign = WhatsappCampaign::create($data);

        return response()->json($campaign, 201);
    }

    public function update(Request $request, WhatsappCampaign $whatsappCampaign)
    {
        $data = $request->validate([
            'name'       => 'sometimes|string|max:255',
            'start_date' => 'sometimes|date',
            'end_date'   => 'nullable|date|after_or_equal:start_date',
            'budget'     => 'sometimes|numeric|min:0',
            'notes'      => 'nullable|string',
        ]);

        $whatsappCampaign->update($data);

        return response()->json($whatsappCampaign);
    }

    public function destroy(WhatsappCampaign $whatsappCampaign)
    {
        $whatsappCampaign->delete();
        return response()->json(null, 204);
    }
}
