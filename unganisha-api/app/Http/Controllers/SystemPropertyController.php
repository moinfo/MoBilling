<?php

namespace App\Http\Controllers;

use App\Http\Requests\StoreSystemPropertyRequest;
use App\Http\Resources\SystemPropertyResource;
use App\Models\SystemProperty;
use Illuminate\Http\Request;

class SystemPropertyController extends Controller
{
    public function index(Request $request)
    {
        $query = SystemProperty::query();

        if ($request->filled('search')) {
            $query->where('name', 'like', '%' . $request->search . '%');
        }

        return SystemPropertyResource::collection(
            $query->orderBy('name')->paginate($request->per_page ?? 50)
        );
    }

    public function store(StoreSystemPropertyRequest $request)
    {
        $property = SystemProperty::create($request->validated());
        return new SystemPropertyResource($property);
    }

    public function show(SystemProperty $system_property)
    {
        return new SystemPropertyResource($system_property);
    }

    public function update(StoreSystemPropertyRequest $request, SystemProperty $system_property)
    {
        $system_property->update($request->validated());
        return new SystemPropertyResource($system_property);
    }

    public function destroy(SystemProperty $system_property)
    {
        $system_property->delete();
        return response()->json(['message' => 'System property deleted']);
    }
}
