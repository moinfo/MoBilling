<?php

namespace App\Notifications;

use App\Channels\SmsChannel;
use App\Channels\WhatsAppChannel;
use App\Models\Document;
use App\Notifications\Concerns\HasTenantBranding;
use App\Services\PdfService;
use App\Services\ReminderTemplateService;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class InvoiceSentNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    public function __construct(public Document $document) {}

    public function via($notifiable): array
    {
        $this->document->loadMissing(['tenant' => fn ($q) => $q->withoutGlobalScopes()]);
        $tenant = $this->document->tenant;

        $channels = [];

        if ($tenant->email_enabled && $notifiable->email) {
            $channels[] = 'mail';
        }

        if ($tenant->sms_enabled && $tenant->reminder_sms_enabled) {
            $channels[] = SmsChannel::class;
        }

        if ($tenant->whatsapp_enabled && $tenant->reminder_whatsapp_enabled) {
            $channels[] = WhatsAppChannel::class;
        }

        // Mobile push: FcmChannel no-ops when FCM_CREDENTIALS is unset and
        // when the client has no registered devices, so it is always safe on.
        $channels[] = \App\Channels\FcmChannel::class;

        return $channels;
    }

    public function toFcm($notifiable): ?array
    {
        $doc = $this->document;
        $typeName = ucfirst($doc->type);

        return [
            'title' => "{$typeName} {$doc->document_number}",
            'body'  => "Amount: " . number_format((float) $doc->total, 2)
                . ($doc->due_date ? ' — due ' . $doc->due_date->format('d M Y') : ''),
            'data'  => ['type' => 'invoice', 'document_id' => $doc->id],
        ];
    }

    public function toWhatsApp($notifiable): array
    {
        $this->document->loadMissing(['tenant' => fn ($q) => $q->withoutGlobalScopes()]);
        $tenant = $this->document->tenant;
        $typeName = ucfirst($this->document->type);
        $amount = $tenant->currency . ' ' . number_format($this->document->total, 2);
        $due = $this->document->due_date?->format('d M Y') ?? '—';
        $payable = $tenant->pesapal_enabled && $this->document->balance_due > 0;

        if ($payable) {
            return [
                'template' => 'invoice_notice_v2',
                'parameters' => ["{$typeName} {$this->document->document_number}", $amount, $due, $tenant->name],
                'language' => 'en',
                'button_url' => (string) $this->document->id,
                'fallback' => "📄 {$typeName} {$this->document->document_number} — {$amount}, due {$due}. Pay online: " . $this->tenantPortalUrl($tenant, "/pay/{$this->document->id}") . " — {$tenant->name}",
            ];
        }

        return [
            'template' => 'invoice_notice_v1',
            'parameters' => ["{$typeName} {$this->document->document_number}", $amount, $due, 'Contact us for payment options', $tenant->name],
            'language' => 'en',
            'fallback' => "📄 {$typeName} {$this->document->document_number} — {$amount}, due {$due}. — {$tenant->name}",
        ];
    }

    public function toSms($notifiable): ?string
    {
        $this->document->loadMissing('client');
        $this->document->loadMissing(['tenant' => fn ($q) => $q->withoutGlobalScopes()]);
        $tenant = $this->document->tenant;
        $typeName = ucfirst($this->document->type);

        $msg = "{$typeName} {$this->document->document_number} for {$tenant->currency} "
            . number_format($this->document->total, 2)
            . ($this->document->due_date ? " due {$this->document->due_date->format('d M Y')}" : '')
            . ". — {$tenant->name}";

        if ($this->document->type === 'invoice' && $tenant->pesapal_enabled && $this->document->balance_due > 0) {
            $payUrl = $this->tenantPortalUrl($this->document->tenant, "/pay/{$this->document->id}");
            $msg .= " Pay: {$payUrl}";
        }

        return $msg;
    }

    public function toMail($notifiable): MailMessage
    {
        $this->document->load('items', 'client');
        $this->document->loadMissing(['tenant' => fn ($q) => $q->withoutGlobalScopes()]);

        $tenant = $this->document->tenant;
        $templateService = app(ReminderTemplateService::class);
        $typeName = ucfirst($this->document->type);

        // Subject: use tenant template or default
        $defaultSubject = "{$typeName} {$this->document->document_number} — {$tenant->name}";
        $subject = $tenant->invoice_email_subject
            ? $templateService->renderDocument($tenant->invoice_email_subject, $this->document, $tenant)
            : $defaultSubject;

        // Body: use tenant template or default
        $defaultBody = "Hello {$this->document->client->name},\n\n"
            . "Please find attached your {$typeName}.\n\n"
            . "Amount: {$tenant->currency} " . number_format($this->document->total, 2) . "\n"
            . ($this->document->due_date ? "Due date: {$this->document->due_date->format('d M Y')}\n" : '')
            . "\nThank you for your business.";
        $body = $tenant->invoice_email_body
            ? $templateService->renderDocument($tenant->invoice_email_body, $this->document, $tenant)
            : null;

        $pdf = app(PdfService::class)->generate($this->document);
        $pdfContent = $pdf->output();

        $mail = (new MailMessage)->subject($subject);

        if ($body) {
            // Custom template — render each line
            foreach (explode("\n", $body) as $line) {
                $mail->line($line ?: ' ');
            }
        } else {
            // Default structured email
            $mail->greeting("Hello {$this->document->client->name},")
                ->line("Please find attached your {$typeName}.")
                ->line("Amount: {$tenant->currency} " . number_format($this->document->total, 2));
            if ($this->document->due_date) {
                $mail->line("Due date: {$this->document->due_date->format('d M Y')}");
            }
            $mail->line('Thank you for your business.');
        }

        // Add "Pay Now" button if tenant has Pesapal enabled and invoice has balance
        if ($this->document->type === 'invoice'
            && $tenant->pesapal_enabled
            && $this->document->balance_due > 0
        ) {
            $payUrl = $this->tenantPortalUrl($this->document->tenant, "/pay/{$this->document->id}");
            $mail->action('Pay Now', $payUrl);
        }

        $this->applyBranding($mail, $tenant);

        return $mail->attachData($pdfContent, "{$this->document->document_number}.pdf", [
            'mime' => 'application/pdf',
        ]);
    }
}
