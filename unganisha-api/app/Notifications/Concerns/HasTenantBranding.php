<?php

namespace App\Notifications\Concerns;

use App\Models\Tenant;
use Illuminate\Notifications\Messages\MailMessage;

trait HasTenantBranding
{
    /**
     * Apply tenant logo, name, and footer to a MailMessage.
     */
    protected function applyBranding(MailMessage $message, Tenant $tenant): MailMessage
    {
        $message->viewData['tenantBranding'] = [
            'name' => $tenant->name,
            'logo_url' => $tenant->logo_url,
            'footer_text' => $tenant->email_footer_text,
        ];

        return $message;
    }
}
