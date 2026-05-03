<?php

namespace App\Http\Controllers;

use App\Models\Document;
use App\Traits\AuthorizesPermissions;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;

class SettingsController extends Controller
{
    use AuthorizesPermissions;
    public function updateCompany(Request $request)
    {
        $this->authorizePermission('settings.company');

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
        $this->authorizePermission('settings.company');

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
                'email_enabled', 'sms_enabled',
                'reminder_sms_enabled', 'reminder_email_enabled',
                'whatsapp_enabled', 'reminder_whatsapp_enabled',
            ]),
        ]);
    }

    public function updateReminderSettings(Request $request)
    {
        $this->authorizePermission('settings.reminders');

        $validated = $request->validate([
            'email_enabled'             => 'boolean',
            'sms_enabled'               => 'boolean',
            'reminder_sms_enabled'      => 'boolean',
            'reminder_email_enabled'    => 'boolean',
            'whatsapp_enabled'          => 'boolean',
            'reminder_whatsapp_enabled' => 'boolean',
        ]);

        $tenant = $request->user()->tenant;
        $tenant->update($validated);

        return response()->json([
            'data'    => $tenant->fresh()->only([
                'email_enabled', 'sms_enabled',
                'reminder_sms_enabled', 'reminder_email_enabled',
                'whatsapp_enabled', 'reminder_whatsapp_enabled',
            ]),
            'message' => 'Reminder settings updated.',
        ]);
    }

    public function getWhatsApp(Request $request)
    {
        $tenant = $request->user()->tenant;

        return response()->json([
            'data' => [
                'whatsapp_enabled' => (bool) $tenant->whatsapp_enabled,
                'reminder_whatsapp_enabled' => (bool) $tenant->reminder_whatsapp_enabled,
                'whatsapp_phone_number_id' => $tenant->whatsapp_phone_number_id,
                'whatsapp_access_token_set' => (bool) $tenant->whatsapp_access_token,
                'whatsapp_business_account_id' => $tenant->whatsapp_business_account_id,
            ],
        ]);
    }

    public function updateWhatsApp(Request $request)
    {
        $this->authorizePermission('settings.reminders');

        $validated = $request->validate([
            'whatsapp_enabled'             => 'required|boolean',
            'reminder_whatsapp_enabled'    => 'required|boolean',
            'whatsapp_phone_number_id'     => 'nullable|string|max:255',
            'whatsapp_access_token'        => 'nullable|string|max:1000',
            'whatsapp_business_account_id' => 'nullable|string|max:255',
        ]);

        $tenant = $request->user()->tenant;

        $update = [
            'whatsapp_enabled' => $validated['whatsapp_enabled'],
            'reminder_whatsapp_enabled' => $validated['reminder_whatsapp_enabled'],
            'whatsapp_phone_number_id' => $validated['whatsapp_phone_number_id'],
            'whatsapp_business_account_id' => $validated['whatsapp_business_account_id'],
        ];

        // Only update token if provided (not masked)
        if (!empty($validated['whatsapp_access_token'])) {
            $update['whatsapp_access_token'] = $validated['whatsapp_access_token'];
        }

        $tenant->update($update);

        return response()->json([
            'data' => [
                'whatsapp_enabled' => (bool) $tenant->whatsapp_enabled,
                'reminder_whatsapp_enabled' => (bool) $tenant->reminder_whatsapp_enabled,
                'whatsapp_phone_number_id' => $tenant->whatsapp_phone_number_id,
                'whatsapp_access_token_set' => (bool) $tenant->whatsapp_access_token,
                'whatsapp_business_account_id' => $tenant->whatsapp_business_account_id,
            ],
            'message' => 'WhatsApp settings updated.',
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
        $this->authorizePermission('settings.payment_methods');

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

    public function getSubscriptionSettings(Request $request)
    {
        $tenant = $request->user()->tenant;

        return response()->json([
            'data' => $tenant->only(['subscription_grace_days']),
        ]);
    }

    public function updateSubscriptionSettings(Request $request)
    {
        $this->authorizePermission('settings.reminders');

        $validated = $request->validate([
            'subscription_grace_days' => 'required|integer|min:1|max:90',
        ]);

        $tenant = $request->user()->tenant;
        $tenant->update($validated);

        return response()->json([
            'data'    => $tenant->fresh()->only(['subscription_grace_days']),
            'message' => 'Subscription settings updated.',
        ]);
    }

    public function getPesapal(Request $request)
    {
        $tenant = $request->user()->tenant;

        return response()->json([
            'data' => [
                'pesapal_enabled' => (bool) $tenant->pesapal_enabled,
                'pesapal_consumer_key' => $tenant->pesapal_consumer_key ? '••••' . substr($tenant->pesapal_consumer_key, -6) : null,
                'pesapal_consumer_key_set' => (bool) $tenant->pesapal_consumer_key,
                'pesapal_consumer_secret_set' => (bool) $tenant->pesapal_consumer_secret,
                'pesapal_ipn_id' => $tenant->pesapal_ipn_id,
                'pesapal_sandbox' => (bool) $tenant->pesapal_sandbox,
            ],
        ]);
    }

    public function updatePesapal(Request $request)
    {
        $this->authorizePermission('settings.payment_methods');

        $validated = $request->validate([
            'pesapal_enabled' => 'required|boolean',
            'pesapal_consumer_key' => 'nullable|string|max:255',
            'pesapal_consumer_secret' => 'nullable|string|max:255',
            'pesapal_sandbox' => 'required|boolean',
        ]);

        $tenant = $request->user()->tenant;

        // Only update credentials if provided (not masked)
        $update = [
            'pesapal_enabled' => $validated['pesapal_enabled'],
            'pesapal_sandbox' => $validated['pesapal_sandbox'],
        ];

        if (!empty($validated['pesapal_consumer_key'])) {
            $update['pesapal_consumer_key'] = $validated['pesapal_consumer_key'];
        }
        if (!empty($validated['pesapal_consumer_secret'])) {
            $update['pesapal_consumer_secret'] = $validated['pesapal_consumer_secret'];
        }

        $tenant->update($update);

        // Auto-register IPN if credentials are set and no IPN ID yet
        if ($tenant->pesapal_consumer_key && $tenant->pesapal_consumer_secret && !$tenant->pesapal_ipn_id) {
            try {
                $pesapal = new \App\Services\TenantPesapalService($tenant);
                $ipnUrl = config('app.url') . '/api/tenant-pesapal/ipn';
                $result = $pesapal->registerIpn($ipnUrl, 'GET');
                $tenant->update(['pesapal_ipn_id' => $result['ipn_id'] ?? null]);
            } catch (\Throwable $e) {
                // Return success but note IPN failed
                return response()->json([
                    'data' => $tenant->fresh()->only(['pesapal_enabled', 'pesapal_sandbox', 'pesapal_ipn_id']),
                    'message' => 'Pesapal settings saved. IPN registration failed: ' . $e->getMessage(),
                ], 200);
            }
        }

        return response()->json([
            'data' => [
                'pesapal_enabled' => (bool) $tenant->pesapal_enabled,
                'pesapal_ipn_id' => $tenant->pesapal_ipn_id,
                'pesapal_sandbox' => (bool) $tenant->pesapal_sandbox,
            ],
            'message' => 'Pesapal settings updated.',
        ]);
    }

    public function getLateFeeSettings(Request $request)
    {
        $tenant = $request->user()->tenant;

        return response()->json([
            'data' => $tenant->only(['late_fee_enabled', 'late_fee_percent', 'late_fee_days']),
        ]);
    }

    public function updateLateFeeSettings(Request $request)
    {
        $this->authorizePermission('settings.reminders');

        $validated = $request->validate([
            'late_fee_enabled' => 'required|boolean',
            'late_fee_percent' => 'required|numeric|min:0.01|max:100',
            'late_fee_days'    => 'required|integer|min:1|max:365',
        ]);

        $tenant = $request->user()->tenant;
        $tenant->update($validated);

        return response()->json([
            'data'    => $tenant->fresh()->only(['late_fee_enabled', 'late_fee_percent', 'late_fee_days']),
            'message' => 'Late fee settings updated.',
        ]);
    }

    public function getLateFeeCount(Request $request)
    {
        $this->authorizePermission('settings.reminders');

        $tenant = $request->user()->tenant;

        $count = Document::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->where('type', 'invoice')
            ->whereIn('status', ['sent', 'overdue', 'partial'])
            ->whereNotNull('overdue_stage')
            ->whereHas('items', fn ($q) => $q->where('description', 'like', 'Late payment fee%'))
            ->count();

        return response()->json(['count' => $count]);
    }

    public function revertLateFees(Request $request)
    {
        $this->authorizePermission('settings.reminders');

        $validated = $request->validate([
            'update_totals' => 'required|boolean',
        ]);

        $tenant = $request->user()->tenant;

        $documents = Document::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->where('type', 'invoice')
            ->whereIn('status', ['sent', 'overdue', 'partial'])
            ->whereNotNull('overdue_stage')
            ->whereHas('items', fn ($q) => $q->where('description', 'like', 'Late payment fee%'))
            ->with(['items' => fn ($q) => $q->where('description', 'like', 'Late payment fee%')])
            ->get();

        $count = $documents->count();

        DB::transaction(function () use ($documents, $validated) {
            foreach ($documents as $document) {
                $feeTotal = $document->items->sum('total');

                foreach ($document->items as $item) {
                    $item->delete();
                }

                $updates = ['overdue_stage' => null];

                if ($validated['update_totals']) {
                    $updates['subtotal'] = max(0, round((float) $document->subtotal - $feeTotal, 2));
                    $updates['total']    = max(0, round((float) $document->total - $feeTotal, 2));
                }

                $document->update($updates);
            }
        });

        return response()->json([
            'message' => "{$count} invoice(s) updated — late fee line items removed.",
            'count'   => $count,
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
        $this->authorizePermission('settings.templates');

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
