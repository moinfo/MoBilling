<?php

namespace App\Http\Controllers;

use App\Exceptions\RegistrarApiException;
use App\Models\RegistrarAccount;
use App\Services\Registrar\FredHttpDriver;
use Illuminate\Http\Request;

/**
 * Tenant-facing registrar account management. Tenants see the shared platform
 * account (read-only) and can manage their own accreditation if they have one.
 */
class RegistrarAccountController extends Controller
{
    public function index()
    {
        $tenantId = auth()->user()->tenant_id;

        $accounts = RegistrarAccount::withCount('domains')
            ->where(fn ($q) => $q->where('tenant_id', $tenantId)->orWhereNull('tenant_id'))
            ->orderByRaw('tenant_id IS NULL')
            ->get()
            ->map(fn ($a) => [
                'id'           => $a->id,
                'name'         => $a->name,
                'driver'       => $a->driver,
                'registrar_id' => $a->registrar_id,
                // endpoint is non-sensitive (the service token is never returned)
                'endpoint_url' => is_null($a->tenant_id) ? null : $a->endpoint_url,
                'has_token'    => !empty($a->credentials['service_token'] ?? null),
                'is_active'    => $a->is_active,
                'is_sandbox'   => $a->is_sandbox,
                'is_platform'  => is_null($a->tenant_id),
                'domains_count'=> $a->domains_count,
            ]);

        return response()->json(['data' => $accounts]);
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'name'          => 'required|string|max:255',
            'endpoint_url'  => 'required|url',
            'registrar_id'  => 'nullable|string|max:255',
            'service_token' => 'required|string',
            'is_active'     => 'boolean',
        ]);

        $account = RegistrarAccount::create([
            'tenant_id'    => auth()->user()->tenant_id,
            'name'         => $data['name'],
            'driver'       => 'fred_epp',
            'endpoint_url' => $data['endpoint_url'],
            'registrar_id' => $data['registrar_id'] ?? null,
            'credentials'  => ['service_token' => $data['service_token']],
            'is_active'    => $data['is_active'] ?? true,
        ]);

        return response()->json(['data' => $account], 201);
    }

    public function update(Request $request, RegistrarAccount $registrarAccount)
    {
        // Tenants may only edit their own accreditation, never the platform row.
        abort_unless($registrarAccount->tenant_id === auth()->user()->tenant_id, 403);

        $data = $request->validate([
            'name'          => 'sometimes|string|max:255',
            'endpoint_url'  => 'sometimes|url',
            'registrar_id'  => 'nullable|string|max:255',
            'service_token' => 'nullable|string',
            'is_active'     => 'boolean',
        ]);

        if (!empty($data['service_token'])) {
            $registrarAccount->credentials = ['service_token' => $data['service_token']];
        }
        unset($data['service_token']);
        $registrarAccount->fill($data)->save();

        return response()->json(['data' => $registrarAccount->fresh()]);
    }

    public function destroy(RegistrarAccount $registrarAccount)
    {
        abort_unless($registrarAccount->tenant_id === auth()->user()->tenant_id, 403);

        if ($registrarAccount->domains()->exists()) {
            return response()->json(['message' => 'Account has domains attached — deactivate it instead.'], 422);
        }

        $registrarAccount->delete();
        return response()->json(null, 204);
    }

    /** "Test connection" — read-only registry credit query. */
    public function test(RegistrarAccount $registrarAccount)
    {
        $tenantId = auth()->user()->tenant_id;
        abort_unless(is_null($registrarAccount->tenant_id) || $registrarAccount->tenant_id === $tenantId, 403);

        try {
            $credits = (new FredHttpDriver($registrarAccount))->credit();
            return response()->json([
                'ok'      => true,
                'credits' => collect($credits)->filter(fn ($c) => (float) $c['credit'] > 0)->values(),
            ]);
        } catch (RegistrarApiException $e) {
            return response()->json(['ok' => false, 'message' => $e->getMessage()], 422);
        }
    }
}
