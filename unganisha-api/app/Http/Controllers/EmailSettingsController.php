<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Mail;

class EmailSettingsController extends Controller
{
    public function show(Request $request)
    {
        $tenant = $request->user()->tenant;

        return response()->json([
            'data' => [
                'email_enabled'  => $tenant->email_enabled,
                'smtp_host'       => $tenant->smtp_host,
                'smtp_port'       => $tenant->smtp_port,
                'smtp_username'   => $tenant->smtp_username,
                'smtp_encryption' => $tenant->smtp_encryption,
                'smtp_from_email' => $tenant->smtp_from_email,
                'smtp_from_name'  => $tenant->smtp_from_name,
                'has_password'    => !empty($tenant->smtp_password),
            ],
        ]);
    }

    public function update(Request $request)
    {
        $tenant = $request->user()->tenant;

        if (!$tenant->email_enabled) {
            return response()->json(['message' => 'Email has been disabled by the administrator.'], 403);
        }

        if ($request->user()->role !== 'admin') {
            return response()->json(['message' => 'Only admins can update email settings.'], 403);
        }

        $validated = $request->validate([
            'smtp_host'       => 'nullable|string|max:255',
            'smtp_port'       => 'nullable|integer|min:1|max:65535',
            'smtp_username'   => 'nullable|string|max:255',
            'smtp_password'   => 'nullable|string|max:255',
            'smtp_encryption' => 'nullable|in:tls,ssl,none',
            'smtp_from_email' => 'nullable|email|max:255',
            'smtp_from_name'  => 'nullable|string|max:255',
        ]);

        // Only update password if a non-empty value was provided
        if (!array_key_exists('smtp_password', $validated) || $validated['smtp_password'] === null || $validated['smtp_password'] === '') {
            unset($validated['smtp_password']);
        }

        $tenant->update($validated);

        return response()->json([
            'data' => [
                'email_enabled'  => $tenant->email_enabled,
                'smtp_host'       => $tenant->smtp_host,
                'smtp_port'       => $tenant->smtp_port,
                'smtp_username'   => $tenant->smtp_username,
                'smtp_encryption' => $tenant->smtp_encryption,
                'smtp_from_email' => $tenant->smtp_from_email,
                'smtp_from_name'  => $tenant->smtp_from_name,
                'has_password'    => !empty($tenant->smtp_password),
            ],
        ]);
    }

    public function test(Request $request)
    {
        $tenant = $request->user()->tenant;

        if (!$tenant->email_enabled) {
            return response()->json(['message' => 'Email has been disabled by the administrator.'], 403);
        }

        if (!$tenant->smtp_host || !$tenant->smtp_port) {
            return response()->json(['message' => 'SMTP settings are not configured.'], 422);
        }

        try {
            $config = [
                'transport'  => 'smtp',
                'host'       => $tenant->smtp_host,
                'port'       => $tenant->smtp_port,
                'username'   => $tenant->smtp_username,
                'password'   => $tenant->smtp_password,
                'encryption' => $tenant->smtp_encryption === 'none' ? null : $tenant->smtp_encryption,
            ];

            config(['mail.mailers.tenant_test' => $config]);

            $fromEmail = $tenant->smtp_from_email ?: $tenant->email;
            $fromName  = $tenant->smtp_from_name ?: $tenant->name;

            Mail::mailer('tenant_test')
                ->raw('This is a test email from MoBilling to verify your SMTP settings.', function ($message) use ($request, $fromEmail, $fromName) {
                    $message->to($request->user()->email)
                            ->from($fromEmail, $fromName)
                            ->subject('MoBilling - SMTP Test');
                });

            return response()->json(['message' => 'Test email sent to ' . $request->user()->email]);
        } catch (\Exception $e) {
            return response()->json(['message' => 'Failed to send test email: ' . $e->getMessage()], 422);
        }
    }
}
