<?php

namespace App\Http\Controllers;

use App\Exceptions\WhmApiException;
use App\Models\Server;
use App\Services\WhmService;
use Illuminate\Http\Request;

class ServerController extends Controller
{
    public function index()
    {
        return response()->json([
            'data' => Server::withCount('hostingAccounts')->orderBy('name')->get(),
        ]);
    }

    public function store(Request $request)
    {
        $data = $this->validated($request);
        $server = Server::create($data);

        return response()->json(['data' => $server], 201);
    }

    public function update(Request $request, Server $server)
    {
        $data = $this->validated($request, updating: true);

        // Keep the stored token when the field is left blank on edit.
        if (empty($data['api_token'])) {
            unset($data['api_token']);
        }

        $server->update($data);

        return response()->json(['data' => $server->fresh()]);
    }

    public function destroy(Server $server)
    {
        if ($server->hostingAccounts()->exists()) {
            return response()->json(['message' => 'Server has hosting accounts and cannot be deleted. Deactivate it instead.'], 422);
        }

        $server->delete();
        return response()->json(null, 204);
    }

    /** "Test connection" — lists WHM packages; also used to populate package selects. */
    public function test(Server $server)
    {
        try {
            $packages = (new WhmService($server))->listPackages();
            return response()->json(['ok' => true, 'packages' => $packages]);
        } catch (WhmApiException $e) {
            return response()->json(['ok' => false, 'message' => $e->getMessage()], 422);
        }
    }

    private function validated(Request $request, bool $updating = false): array
    {
        $required = $updating ? 'sometimes' : 'required';

        return $request->validate([
            'name'       => "{$required}|string|max:255",
            'hostname'   => "{$required}|string|max:255",
            'port'       => 'integer|min:1|max:65535',
            'username'   => "{$required}|string|max:255",
            'api_token'  => ($updating ? 'nullable' : 'required') . '|string',
            'nameservers'=> 'nullable|array',
            'is_active'  => 'boolean',
            'verify_ssl' => 'boolean',
        ]);
    }
}
