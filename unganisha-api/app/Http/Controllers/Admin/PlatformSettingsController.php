<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\PlatformSetting;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PlatformSettingsController extends Controller
{
    private function authorize(): void
    {
        if (!auth()->user()->isSuperAdmin()) {
            abort(403, 'Unauthorized');
        }
    }

    public function index(): JsonResponse
    {
        $this->authorize();

        $settings = PlatformSetting::all()->pluck('value', 'key');

        return response()->json(['data' => $settings]);
    }

    public function update(Request $request): JsonResponse
    {
        $this->authorize();

        $request->validate([
            'platform_bank_name' => 'nullable|string|max:255',
            'platform_bank_account_name' => 'nullable|string|max:255',
            'platform_bank_account_number' => 'nullable|string|max:255',
            'platform_bank_branch' => 'nullable|string|max:255',
            'platform_payment_instructions' => 'nullable|string|max:1000',
            // Email templates
            'welcome_email_subject' => 'nullable|string|max:255',
            'welcome_email_body' => 'nullable|string|max:5000',
            'reset_password_email_subject' => 'nullable|string|max:255',
            'reset_password_email_body' => 'nullable|string|max:5000',
            'new_tenant_email_subject' => 'nullable|string|max:255',
            'new_tenant_email_body' => 'nullable|string|max:5000',
            'sms_activation_email_subject' => 'nullable|string|max:255',
            'sms_activation_email_body' => 'nullable|string|max:5000',
        ]);

        $allowedKeys = [
            'platform_bank_name',
            'platform_bank_account_name',
            'platform_bank_account_number',
            'platform_bank_branch',
            'platform_payment_instructions',
            // Email templates
            'welcome_email_subject',
            'welcome_email_body',
            'reset_password_email_subject',
            'reset_password_email_body',
            'new_tenant_email_subject',
            'new_tenant_email_body',
            'sms_activation_email_subject',
            'sms_activation_email_body',
        ];

        foreach ($allowedKeys as $key) {
            if ($request->has($key)) {
                PlatformSetting::set($key, $request->input($key));
            }
        }

        $settings = PlatformSetting::all()->pluck('value', 'key');

        return response()->json([
            'message' => 'Platform settings updated.',
            'data' => $settings,
        ]);
    }
}
