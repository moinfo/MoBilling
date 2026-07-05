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
                // credential material is never returned — only whether it's present
                'host'         => is_null($a->tenant_id) ? null : ($a->credentials['host'] ?? null),
                'has_cert'     => !empty($a->credentials['certificate'] ?? null),
                'has_key'      => !empty($a->credentials['private_key'] ?? null),
                'is_active'    => $a->is_active,
                'is_sandbox'   => $a->is_sandbox,
                'is_platform'  => is_null($a->tenant_id),
                'domains_count'=> $a->domains_count,
            ]);

        return response()->json(['data' => $accounts]);
    }

    // Validate the PEM material TCRA issues (MOINFOTECH.crt / MOINFOTECH.key).
    private function credentialRules(bool $creating): array
    {
        $req = $creating ? 'required' : 'nullable';

        return [
            'name'         => ($creating ? 'required' : 'sometimes') . '|string|max:255',
            'registrar_id' => ($creating ? 'required' : 'sometimes') . '|string|max:255', // EPP username/handle
            'password'     => "$req|string",
            'certificate'  => [$req, 'string', fn ($a, $v, $f) => $v && !str_contains($v, 'BEGIN CERTIFICATE') ? $f('That does not look like a PEM certificate (.crt).') : null],
            'private_key'  => [$req, 'string', fn ($a, $v, $f) => $v && !str_contains($v, 'PRIVATE KEY') ? $f('That does not look like a PEM private key (.key).') : null],
            'host'         => 'nullable|string|max:255',
            'port'         => 'nullable|integer|min:1|max:65535',
            'is_sandbox'   => 'boolean',
            'is_active'    => 'boolean',
        ];
    }

    public function store(Request $request)
    {
        $data = $request->validate($this->credentialRules(true));

        // MoBilling reaches the registry through the FRED-EPP bridge; tenants
        // don't pick that — reuse the platform bridge, but with THEIR EPP creds.
        $bridge = RegistrarAccount::whereNull('tenant_id')->value('endpoint_url');

        $account = RegistrarAccount::create([
            'tenant_id'    => auth()->user()->tenant_id,
            'name'         => $data['name'],
            'driver'       => 'fred_epp',
            'endpoint_url' => $bridge,
            'registrar_id' => $data['registrar_id'],
            'credentials'  => [
                'password'    => $data['password'],
                'certificate' => $data['certificate'],
                'private_key' => $data['private_key'],
                'host'        => $data['host'] ?? 'mtanzania.tznic.or.tz',
                'port'        => $data['port'] ?? 700,
            ],
            'is_sandbox'   => $data['is_sandbox'] ?? false,
            'is_active'    => $data['is_active'] ?? true,
        ]);

        return response()->json(['data' => ['id' => $account->id]], 201);
    }

    public function update(Request $request, RegistrarAccount $registrarAccount)
    {
        // Tenants may only edit their own accreditation, never the platform row.
        abort_unless($registrarAccount->tenant_id === auth()->user()->tenant_id, 403);

        $data = $request->validate($this->credentialRules(false));

        // Merge secrets: only overwrite the ones actually re-supplied.
        $creds = $registrarAccount->credentials ?? [];
        foreach (['password', 'certificate', 'private_key'] as $k) {
            if (!empty($data[$k])) {
                $creds[$k] = $data[$k];
            }
        }
        if (array_key_exists('host', $data) && $data['host']) {
            $creds['host'] = $data['host'];
        }
        if (array_key_exists('port', $data) && $data['port']) {
            $creds['port'] = (int) $data['port'];
        }
        $registrarAccount->credentials = $creds;

        foreach (['name', 'registrar_id', 'is_sandbox', 'is_active'] as $k) {
            if (array_key_exists($k, $data)) {
                $registrarAccount->{$k} = $data[$k];
            }
        }
        $registrarAccount->save();

        return response()->json(['data' => ['id' => $registrarAccount->id]]);
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

        // Tenant accounts connect to the registry under their OWN cert/handle
        // (the bridge accepts per-account creds). Guard against half-entered
        // credentials before attempting a live connection.
        if (!is_null($registrarAccount->tenant_id)) {
            $c = $registrarAccount->credentials ?? [];
            if (empty($c['certificate']) || empty($c['private_key']) || empty($c['password'])) {
                return response()->json([
                    'ok'      => false,
                    'message' => 'Missing credentials — add your handle, password, certificate (.crt) and key (.key).',
                ], 200);
            }
        }

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
