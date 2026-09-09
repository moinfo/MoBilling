<?php

namespace App\Http\Controllers;

use App\Exceptions\MikrotikApiException;
use App\Http\Requests\StoreMikrotikRouterRequest;
use App\Http\Resources\MikrotikRouterResource;
use App\Models\MikrotikRouter;
use App\Services\Mikrotik\RouterOsService;
use Illuminate\Http\Request;

class MikrotikRouterController extends Controller
{
    public function index(Request $request)
    {
        $query = MikrotikRouter::query();

        if ($request->filled('search')) {
            $query->where(function ($q) use ($request) {
                $q->where('name', 'like', '%' . $request->search . '%')
                  ->orWhere('host', 'like', '%' . $request->search . '%');
            });
        }

        return MikrotikRouterResource::collection(
            $query->orderBy('name')->paginate($request->per_page ?? 50)
        );
    }

    public function store(StoreMikrotikRouterRequest $request)
    {
        $router = MikrotikRouter::create($request->validated());
        return new MikrotikRouterResource($router);
    }

    public function show(MikrotikRouter $mikrotik_router)
    {
        return new MikrotikRouterResource($mikrotik_router);
    }

    public function update(StoreMikrotikRouterRequest $request, MikrotikRouter $mikrotik_router)
    {
        $data = $request->validated();
        if (empty($data['password'])) {
            unset($data['password']); // keep the current password
        }

        $mikrotik_router->update($data);
        return new MikrotikRouterResource($mikrotik_router);
    }

    public function destroy(MikrotikRouter $mikrotik_router)
    {
        $mikrotik_router->delete();
        return response()->json(['message' => 'Router deleted']);
    }

    public function test(MikrotikRouter $mikrotik_router)
    {
        try {
            $result = (new RouterOsService($mikrotik_router))->testConnection();
            $mikrotik_router->update([
                'last_tested_at'    => now(),
                'last_test_status'  => 'success',
                'last_test_message' => $result['message'],
            ]);

            return response()->json(['data' => ['ok' => true, 'message' => $result['message']]]);
        } catch (MikrotikApiException $e) {
            $mikrotik_router->update([
                'last_tested_at'    => now(),
                'last_test_status'  => 'failed',
                'last_test_message' => $e->getMessage(),
            ]);

            return response()->json(['data' => ['ok' => false, 'message' => $e->getMessage()]], 422);
        }
    }
}
