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

    /** GET the WHM package list for populating change-package selects. */
    public function packages(Server $server)
    {
        try {
            return response()->json(['data' => (new WhmService($server))->listPackages()]);
        } catch (WhmApiException $e) {
            return response()->json(['message' => $e->getMessage(), 'data' => []], 422);
        }
    }

    /** GET the WHM package list with resource-limit specs, for auto-filling a catalog description. */
    public function packagesDetailed(Server $server)
    {
        try {
            return response()->json(['data' => (new WhmService($server))->listPackagesDetailed()]);
        } catch (WhmApiException $e) {
            return response()->json(['message' => $e->getMessage(), 'data' => []], 422);
        }
    }

    /** GET server vitals: hostname, WHM version, load average. */
    public function health(Server $server)
    {
        try {
            return response()->json(['data' => (new WhmService($server))->serverHealth()]);
        } catch (WhmApiException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }
    }

    /**
     * Creates a WHM package. WHM silently prefixes whatever name is given
     * with this reseller's own username (verified live: every existing
     * package here already carries that prefix) — the response's `name`
     * is the real one, not the one submitted.
     */
    public function storePackage(Request $request, Server $server)
    {
        $data = $this->validatedPackage($request);
        $whm = new WhmService($server);

        try {
            $whm->createPackage($data['name'], $data);
            return response()->json(['data' => ['name' => $whm->prefixedPackageName($data['name'])] + $data]);
        } catch (WhmApiException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }
    }

    /** Edits an existing package's limits by its real (already-prefixed) name — does not rename it. */
    public function updatePackage(Request $request, Server $server, string $package)
    {
        $data = $this->validatedPackage($request, updating: true);

        try {
            (new WhmService($server))->updatePackage($package, $data);
            return response()->json(['data' => ['name' => $package] + $data]);
        } catch (WhmApiException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }
    }

    /** Deletes a package — WHM itself refuses if any account still uses it. */
    public function destroyPackage(Server $server, string $package)
    {
        try {
            (new WhmService($server))->deletePackage($package);
            return response()->json(['message' => 'Package deleted.']);
        } catch (WhmApiException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }
    }

    private function validatedPackage(Request $request, bool $updating = false): array
    {
        // On create, a blank field is left out entirely so WHM applies its
        // own default. On edit there's no real "leave unlimited" WHM will
        // accept for every field (bwlimit=0 is flatly rejected, confirmed
        // live), so every field is required — the frontend always submits
        // the package's current full set of limits, changed or not, never
        // a partial diff.
        $rule = $updating ? 'required|integer|min:0' : 'nullable|integer|min:0';
        $rules = [
            'quota_mb' => $rule,
            'bandwidth_mb' => $rule,
            'databases' => $rule,
            'email_accounts' => $rule,
            'subdomains' => $rule,
            'ftp_accounts' => $rule,
            'addon_domains' => $rule,
            'parked_domains' => $rule,
        ];
        if (!$updating) {
            // Letters/numbers/underscore only — matches WHM's own package-name rules.
            $rules['name'] = 'required|string|max:64|regex:/^[a-zA-Z0-9_]+$/';
        }

        return $request->validate($rules);
    }

    private function validated(Request $request, bool $updating = false): array
    {
        $required = $updating ? 'sometimes' : 'required';

        // Normalize hostname: users paste with stray spaces/commas/schemes.
        if ($request->filled('hostname')) {
            $request->merge(['hostname' => trim(preg_replace('#^https?://#i', '', $request->hostname), " ,;/")]);
        }

        return $request->validate([
            'name'       => "{$required}|string|max:255",
            'hostname'   => ["{$required}", 'string', 'max:255', 'regex:/^[a-z0-9][a-z0-9.-]*[a-z0-9]$/i'],
            'port'       => 'integer|min:1|max:65535',
            'username'   => "{$required}|string|max:255",
            'api_token'  => ($updating ? 'nullable' : 'required') . '|string',
            'nameservers'=> 'nullable|array',
            'is_active'  => 'boolean',
            'verify_ssl' => 'boolean',
        ]);
    }
}
