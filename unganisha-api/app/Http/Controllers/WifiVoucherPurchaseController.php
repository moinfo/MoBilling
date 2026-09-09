<?php

namespace App\Http\Controllers;

use App\Http\Resources\WifiVoucherPurchaseResource;
use App\Models\WifiVoucherPurchase;
use Illuminate\Http\Request;

class WifiVoucherPurchaseController extends Controller
{
    public function index(Request $request)
    {
        $query = WifiVoucherPurchase::with(['router:id,name', 'plan:id,name']);

        if ($request->filled('mikrotik_router_id')) {
            $query->where('mikrotik_router_id', $request->mikrotik_router_id);
        }
        if ($request->filled('status')) {
            $query->where('status', $request->status);
        }
        if ($request->filled('search')) {
            $query->where('customer_phone', 'like', '%' . $request->search . '%');
        }

        return WifiVoucherPurchaseResource::collection(
            $query->orderByDesc('created_at')->paginate($request->per_page ?? 25)
        );
    }

    public function show(WifiVoucherPurchase $wifi_voucher_purchase)
    {
        return new WifiVoucherPurchaseResource($wifi_voucher_purchase->load(['router:id,name', 'plan:id,name']));
    }
}
