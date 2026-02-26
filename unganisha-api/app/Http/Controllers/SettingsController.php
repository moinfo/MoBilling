<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;

class SettingsController extends Controller
{
    public function updateCompany(Request $request)
    {
        if ($request->user()->role !== 'admin') {
            return response()->json(['message' => 'Only admins can update company settings.'], 403);
        }

        $validated = $request->validate([
            'name'                 => 'required|string|max:255',
            'email'                => 'required|email|max:255',
            'phone'                => 'nullable|string|max:50',
            'address'              => 'nullable|string|max:1000',
            'tax_id'               => 'nullable|string|max:100',
            'currency'             => 'required|string|max:10',
            'website'              => 'nullable|url|max:255',
            'bank_name'            => 'nullable|string|max:255',
            'bank_account_name'    => 'nullable|string|max:255',
            'bank_account_number'  => 'nullable|string|max:100',
            'bank_branch'          => 'nullable|string|max:255',
            'payment_instructions' => 'nullable|string|max:2000',
        ]);

        $tenant = $request->user()->tenant;
        $tenant->update($validated);

        return response()->json(['tenant' => $tenant->fresh()]);
    }

    public function uploadLogo(Request $request)
    {
        if ($request->user()->role !== 'admin') {
            return response()->json(['message' => 'Only admins can upload the logo.'], 403);
        }

        $request->validate([
            'logo' => 'required|image|mimes:jpeg,png,webp|max:2048',
        ]);

        $tenant = $request->user()->tenant;

        // Delete old logo if exists
        if ($tenant->logo_path) {
            Storage::disk('public')->delete($tenant->logo_path);
        }

        $ext = $request->file('logo')->getClientOriginalExtension();
        $path = $request->file('logo')->storeAs('logos', "{$tenant->id}.{$ext}", 'public');

        $tenant->update(['logo_path' => $path]);

        return response()->json([
            'logo_url' => $tenant->fresh()->logo_url,
            'message'  => 'Logo uploaded successfully.',
        ]);
    }

    public function updateProfile(Request $request)
    {
        $user = $request->user();

        $validated = $request->validate([
            'name'             => 'required|string|max:255',
            'email'            => 'required|email|max:255|unique:users,email,' . $user->id,
            'phone'            => 'nullable|string|max:50',
            'current_password' => 'nullable|required_with:password|string',
            'password'         => 'nullable|min:8|confirmed',
        ]);

        if (!empty($validated['password'])) {
            if (!Hash::check($validated['current_password'], $user->password)) {
                throw ValidationException::withMessages([
                    'current_password' => ['The current password is incorrect.'],
                ]);
            }
        }

        $user->update([
            'name'  => $validated['name'],
            'email' => $validated['email'],
            'phone' => $validated['phone'] ?? $user->phone,
            ...(!empty($validated['password']) ? ['password' => $validated['password']] : []),
        ]);

        return response()->json(['user' => $user->fresh()->load('tenant')]);
    }

    public function getReminderSettings(Request $request)
    {
        $tenant = $request->user()->tenant;

        return response()->json([
            'data' => $tenant->only([
                'reminder_sms_enabled', 'reminder_email_enabled',
            ]),
        ]);
    }

    public function updateReminderSettings(Request $request)
    {
        if ($request->user()->role !== 'admin') {
            return response()->json(['message' => 'Only admins can update reminder settings.'], 403);
        }

        $validated = $request->validate([
            'reminder_sms_enabled'   => 'boolean',
            'reminder_email_enabled' => 'boolean',
        ]);

        $tenant = $request->user()->tenant;
        $tenant->update($validated);

        return response()->json([
            'data'    => $tenant->fresh()->only([
                'reminder_sms_enabled', 'reminder_email_enabled',
            ]),
            'message' => 'Reminder settings updated.',
        ]);
    }

    private const DEFAULT_PAYMENT_METHODS = [
        ['value' => 'bank', 'label' => 'Bank Transfer', 'details' => [
            ['key' => 'Bank Name', 'value' => ''],
            ['key' => 'Account Name', 'value' => ''],
            ['key' => 'Account Number', 'value' => ''],
            ['key' => 'Branch', 'value' => ''],
        ]],
        ['value' => 'mpesa', 'label' => 'M-Pesa', 'details' => [
            ['key' => 'Paybill / Till Number', 'value' => ''],
            ['key' => 'Account Name', 'value' => ''],
        ]],
        ['value' => 'cash', 'label' => 'Cash', 'details' => []],
        ['value' => 'card', 'label' => 'Card', 'details' => []],
        ['value' => 'cheque', 'label' => 'Cheque', 'details' => []],
    ];

    public function getPaymentMethods(Request $request)
    {
        $tenant = $request->user()->tenant;

        if ($tenant->payment_methods) {
            return response()->json(['data' => $tenant->payment_methods]);
        }

        // First time: seed defaults from existing bank details on the tenant
        $defaults = self::DEFAULT_PAYMENT_METHODS;
        if ($tenant->bank_name || $tenant->bank_account_number) {
            $defaults[0]['details'] = array_filter([
                $tenant->bank_name ? ['key' => 'Bank Name', 'value' => $tenant->bank_name] : null,
                $tenant->bank_account_name ? ['key' => 'Account Name', 'value' => $tenant->bank_account_name] : null,
                $tenant->bank_account_number ? ['key' => 'Account Number', 'value' => $tenant->bank_account_number] : null,
                $tenant->bank_branch ? ['key' => 'Branch', 'value' => $tenant->bank_branch] : null,
            ]);
            $defaults[0]['details'] = array_values($defaults[0]['details']);
        }

        return response()->json(['data' => $defaults]);
    }

    public function updatePaymentMethods(Request $request)
    {
        if ($request->user()->role !== 'admin') {
            return response()->json(['message' => 'Only admins can update payment methods.'], 403);
        }

        $validated = $request->validate([
            'payment_methods' => 'required|array|min:1',
            'payment_methods.*.value' => 'required|string|max:50',
            'payment_methods.*.label' => 'required|string|max:100',
            'payment_methods.*.details' => 'nullable|array',
            'payment_methods.*.details.*.key' => 'required|string|max:100',
            'payment_methods.*.details.*.value' => 'required|string|max:500',
        ]);

        $tenant = $request->user()->tenant;
        $tenant->update(['payment_methods' => $validated['payment_methods']]);

        return response()->json([
            'data' => $tenant->fresh()->payment_methods,
            'message' => 'Payment methods updated.',
        ]);
    }

    private const TEMPLATE_FIELDS = [
        'reminder_email_subject', 'reminder_email_body',
        'overdue_email_subject', 'overdue_email_body',
        'reminder_sms_body', 'overdue_sms_body',
        'invoice_email_subject', 'invoice_email_body',
        'email_footer_text',
    ];

    public function getTemplates(Request $request)
    {
        $tenant = $request->user()->tenant;

        return response()->json([
            'data' => $tenant->only(self::TEMPLATE_FIELDS),
        ]);
    }

    public function updateTemplates(Request $request)
    {
        if ($request->user()->role !== 'admin') {
            return response()->json(['message' => 'Only admins can update templates.'], 403);
        }

        $validated = $request->validate([
            'reminder_email_subject' => 'nullable|string|max:255',
            'reminder_email_body'    => 'nullable|string|max:5000',
            'overdue_email_subject'  => 'nullable|string|max:255',
            'overdue_email_body'     => 'nullable|string|max:5000',
            'reminder_sms_body'      => 'nullable|string|max:160',
            'overdue_sms_body'       => 'nullable|string|max:160',
            'invoice_email_subject'  => 'nullable|string|max:255',
            'invoice_email_body'     => 'nullable|string|max:5000',
            'email_footer_text'      => 'nullable|string|max:500',
        ]);

        $tenant = $request->user()->tenant;
        $tenant->update($validated);

        return response()->json([
            'data'    => $tenant->fresh()->only(self::TEMPLATE_FIELDS),
            'message' => 'Templates updated.',
        ]);
    }
}
