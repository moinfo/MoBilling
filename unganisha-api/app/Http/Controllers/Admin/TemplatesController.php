<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Tenant;

class TemplatesController extends Controller
{
    private const TEMPLATE_FIELDS = [
        'reminder_email_subject', 'reminder_email_body',
        'overdue_email_subject', 'overdue_email_body',
        'reminder_sms_body', 'overdue_sms_body',
        'invoice_email_subject', 'invoice_email_body',
        'email_footer_text',
    ];

    private function authorize(): void
    {
        if (!auth()->user()->isSuperAdmin()) {
            abort(403, 'Unauthorized');
        }
    }

    public function show(Tenant $tenant)
    {
        $this->authorize();

        return response()->json([
            'data' => $tenant->only(self::TEMPLATE_FIELDS),
        ]);
    }

    public function update(\Illuminate\Http\Request $request, Tenant $tenant)
    {
        $this->authorize();

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

        $tenant->update($validated);

        return response()->json([
            'data'    => $tenant->fresh()->only(self::TEMPLATE_FIELDS),
            'message' => 'Templates updated.',
        ]);
    }
}
