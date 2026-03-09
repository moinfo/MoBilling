<?php

namespace App\Http\Controllers\Portal;

use App\Http\Controllers\Controller;
use App\Models\ClientSubscription;
use Illuminate\Http\Request;

class PortalSubscriptionController extends Controller
{
    public function index(Request $request)
    {
        $clientId = $request->user()->client_id;

        $subscriptions = ClientSubscription::where('client_id', $clientId)
            ->with('productService:id,name,type,price')
            ->orderByDesc('start_date')
            ->get();

        return response()->json(['data' => $subscriptions]);
    }
}
