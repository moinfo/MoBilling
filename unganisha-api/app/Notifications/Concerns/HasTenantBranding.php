<?php

namespace App\Notifications\Concerns;

use App\Models\Tenant;
use Illuminate\Notifications\Messages\MailMessage;

trait HasTenantBranding
{
    /**
     * Apply tenant logo, name, footer, and custom SMTP mailer to a MailMessage.
     */
    protected function applyBranding(MailMessage $message, Tenant $tenant): MailMessage
    {
        $message->viewData['tenantBranding'] = [
            'name' => $tenant->name,
            'logo_url' => $tenant->logo_url,
            'footer_text' => $tenant->email_footer_text,
        ];

        // Use tenant's own SMTP if configured, otherwise use platform default
        if ($tenant->smtp_host && $tenant->smtp_port) {
            config(['mail.mailers.tenant_' . $tenant->id => [
                'transport'  => 'smtp',
                'host'       => $tenant->smtp_host,
                'port'       => $tenant->smtp_port,
                'username'   => $tenant->smtp_username,
                'password'   => $tenant->smtp_password,
                'encryption' => $tenant->smtp_encryption === 'none' ? null : $tenant->smtp_encryption,
            ]]);

            $message->mailer('tenant_' . $tenant->id);

            if ($tenant->smtp_from_email) {
                $message->from($tenant->smtp_from_email, $tenant->smtp_from_name ?: $tenant->name);
            }
        }

        return $message;
    }
}
