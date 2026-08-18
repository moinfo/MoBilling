<?php

namespace App\Http\Controllers;

use App\Models\License;
use App\Models\LicenseActivation;
use Illuminate\Http\Request;

/**
 * Public endpoint (no auth) that a self-hosted MoBilling install calls
 * periodically to check whether it's still licensed. Domain-locked,
 * single-activation: a license's domain is null until its first
 * successful validate call, which binds it — after that, a mismatched
 * domain is rejected. An admin can clear the binding via
 * Admin\LicenseController::unbindDomain() to move a license to a new install.
 */
class LicenseValidationController extends Controller
{
    public function validate(Request $request)
    {
        $data = $request->validate([
            'license_key' => 'required|string',
            'domain' => 'required|string|max:255',
            'app_version' => 'nullable|string|max:50',
        ]);

        $license = License::where('license_key', $data['license_key'])->first();
        if (!$license) {
            return response()->json(['valid' => false, 'message' => 'Invalid license key.'], 404);
        }

        if ($license->status === 'suspended') {
            return response()->json(['valid' => false, 'message' => 'This license has been suspended. Contact support.'], 403);
        }

        if ($license->isExpired()) {
            if ($license->status !== 'expired') {
                $license->update(['status' => 'expired']);
            }
            return response()->json(['valid' => false, 'message' => 'This license has expired.'], 403);
        }

        if ($license->domain === null) {
            $license->domain = $data['domain'];
        } elseif ($license->domain !== $data['domain']) {
            return response()->json(['valid' => false, 'message' => 'This license is already active on a different domain.'], 403);
        }

        $license->last_validated_at = now();
        $license->save();

        LicenseActivation::updateOrCreate(
            ['license_id' => $license->id, 'domain' => $data['domain']],
            ['ip_address' => $request->ip(), 'app_version' => $data['app_version'] ?? null, 'last_seen_at' => now()],
        );

        return response()->json([
            'valid' => true,
            'message' => 'OK',
            'customer_name' => $license->customer_name,
            'product' => $license->product,
            'expires_at' => $license->expires_at?->toDateString(),
        ]);
    }
}
