<?php

namespace App\Http\Controllers;

/** Self-hosted customer's own view of their license — irrelevant for SaaS tenants (mobilling.co.tz itself). */
class LicenseStatusController extends Controller
{
    public function show()
    {
        $tenant = auth()->user()->tenant;

        if (!$tenant || !$tenant->is_self_hosted) {
            return response()->json(['message' => 'This install is not self-hosted.'], 404);
        }

        return response()->json(['data' => [
            'license_key' => $this->maskKey($tenant->license_key),
            'status' => $tenant->is_active ? 'active' : 'inactive',
            'expires_at' => $tenant->license_expires_at?->toDateString(),
            'last_checked_at' => $tenant->license_last_valid_at?->toIso8601String(),
            'app_version' => config('app.version'),
        ]]);
    }

    /** Shows only the first and last segment — this is a settings display, not a place to hand out the full key to anyone who can view it. */
    private function maskKey(?string $key): ?string
    {
        if (!$key) {
            return null;
        }
        $parts = explode('-', $key);
        if (count($parts) < 2) {
            return $key;
        }
        $masked = array_fill(1, count($parts) - 2, '****');
        return $parts[0] . '-' . implode('-', $masked) . '-' . end($parts);
    }
}
