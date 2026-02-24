<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Tenant;
use App\Services\ResellerService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class SmsSettingsController extends Controller
{
    private function authorize(): void
    {
        if (!auth()->user()->isSuperAdmin()) {
            abort(403, 'Unauthorized');
        }
    }

    public function show(Tenant $tenant)
    {
        $this->authorize();

        $data = [
            'sms_enabled' => $tenant->sms_enabled,
            'gateway_email' => $tenant->gateway_email,
            'gateway_username' => $tenant->gateway_username,
            'sender_id' => $tenant->sender_id,
            'has_authorization' => !empty($tenant->sms_authorization),
        ];

        // Fetch real-time balance if tenant has SMS configured
        if ($tenant->sms_enabled && $tenant->sms_authorization) {
            try {
                $reseller = new ResellerService();
                $balance = $reseller->getBalance($tenant);
                $data['sms_balance'] = $balance['data']['sms_balance'] ?? $balance['sms_balance'] ?? null;
            } catch (\Throwable $e) {
                Log::warning('Failed to fetch SMS balance', [
                    'tenant_id' => $tenant->id,
                    'error' => $e->getMessage(),
                ]);
                $data['sms_balance'] = null;
                $data['balance_error'] = $e->getMessage();
            }
        }

        return response()->json(['data' => $data]);
    }

    public function update(Request $request, Tenant $tenant)
    {
        $this->authorize();

        $validated = $request->validate([
            'sms_enabled' => 'required|boolean',
            'gateway_email' => 'nullable|email|max:255',
            'gateway_username' => 'nullable|string|max:255',
            'sender_id' => 'nullable|string|max:50',
            'sms_authorization' => 'nullable|string',
        ]);

        // Only update authorization if a non-empty value was provided
        if (!array_key_exists('sms_authorization', $validated) || $validated['sms_authorization'] === null || $validated['sms_authorization'] === '') {
            unset($validated['sms_authorization']);
        }

        $tenant->update($validated);

        return response()->json([
            'data' => [
                'sms_enabled' => $tenant->sms_enabled,
                'gateway_email' => $tenant->gateway_email,
                'gateway_username' => $tenant->gateway_username,
                'sender_id' => $tenant->sender_id,
                'has_authorization' => !empty($tenant->sms_authorization),
            ],
        ]);
    }

    public function recharge(Request $request, Tenant $tenant)
    {
        $this->authorize();

        $data = $request->validate([
            'sms_count' => 'required|integer|min:1',
        ]);

        if (!$tenant->gateway_email) {
            return response()->json(['message' => 'Tenant has no gateway email configured.'], 422);
        }

        try {
            $reseller = new ResellerService();
            $result = $reseller->recharge($tenant->gateway_email, $data['sms_count']);

            Log::info('Admin SMS recharge', [
                'tenant_id' => $tenant->id,
                'sms_count' => $data['sms_count'],
                'admin_id' => auth()->id(),
            ]);

            return response()->json([
                'message' => "Successfully recharged {$data['sms_count']} SMS.",
                'data' => $result,
            ]);
        } catch (\Throwable $e) {
            return response()->json(['message' => 'Recharge failed: ' . $e->getMessage()], 500);
        }
    }

    public function deduct(Request $request, Tenant $tenant)
    {
        $this->authorize();

        $data = $request->validate([
            'sms_count' => 'required|integer|min:1',
        ]);

        if (!$tenant->gateway_email) {
            return response()->json(['message' => 'Tenant has no gateway email configured.'], 422);
        }

        try {
            $reseller = new ResellerService();
            $result = $reseller->deduct($tenant->gateway_email, $data['sms_count']);

            Log::info('Admin SMS deduct', [
                'tenant_id' => $tenant->id,
                'sms_count' => $data['sms_count'],
                'admin_id' => auth()->id(),
            ]);

            return response()->json([
                'message' => "Successfully deducted {$data['sms_count']} SMS.",
                'data' => $result,
            ]);
        } catch (\Throwable $e) {
            return response()->json(['message' => 'Deduction failed: ' . $e->getMessage()], 500);
        }
    }
}
