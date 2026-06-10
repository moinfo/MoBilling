<?php

namespace App\Http\Controllers;

use App\Http\Requests\StoreSystemRequest;
use App\Http\Resources\SystemResource;
use App\Models\System;
use Illuminate\Http\Request;

class SystemController extends Controller
{
    public function index(Request $request)
    {
        $query = System::query();

        if ($request->filled('search')) {
            $query->where('name', 'like', '%' . $request->search . '%');
        }

        return SystemResource::collection(
            $query->orderBy('name')->paginate($request->per_page ?? 50)
        );
    }

    public function store(StoreSystemRequest $request)
    {
        $system = System::create($request->validated());
        return new SystemResource($system);
    }

    public function show(System $system)
    {
        return new SystemResource($system);
    }

    public function update(StoreSystemRequest $request, System $system)
    {
        $system->update($request->validated());
        return new SystemResource($system);
    }

    public function destroy(System $system)
    {
        $system->delete();
        return response()->json(['message' => 'System deleted']);
    }
}
