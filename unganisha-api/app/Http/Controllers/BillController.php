<?php

namespace App\Http\Controllers;

use App\Http\Requests\StoreBillRequest;
use App\Http\Resources\BillResource;
use App\Models\Bill;
use Illuminate\Http\Request;

class BillController extends Controller
{
    public function index(Request $request)
    {
        $query = Bill::with(['payments', 'billCategory.parent']);

        if ($request->has('search')) {
            $query->where('name', 'LIKE', "%{$request->search}%");
        }

        if ($request->has('category')) {
            $query->where('category', $request->category);
        }

        if ($request->boolean('active_only', false)) {
            $query->where('is_active', true);
        }

        return BillResource::collection(
            $query->orderBy('due_date')->paginate($request->per_page ?? 20)
        );
    }

    public function store(StoreBillRequest $request)
    {
        $bill = Bill::create($request->validated());
        return new BillResource($bill);
    }

    public function show(Bill $bill)
    {
        return new BillResource($bill->load(['payments', 'billCategory.parent']));
    }

    public function update(StoreBillRequest $request, Bill $bill)
    {
        $bill->update($request->validated());
        return new BillResource($bill);
    }

    public function destroy(Bill $bill)
    {
        $bill->delete();
        return response()->json(['message' => 'Bill deleted']);
    }
}
