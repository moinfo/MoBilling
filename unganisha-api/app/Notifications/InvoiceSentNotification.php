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

    /**
     * A plain string, not the template/fallback array shape — the approved
     * invoice_notice_v1/v2 templates only carry generic marketing copy ("Tap
     * Pay Now below to pay securely...") with no slot for what the invoice is
     * actually for or offline payment details, which clients have asked for.
     */
    public function toWhatsApp($notifiable): string
    {
        $this->document->loadMissing(['tenant' => fn ($q) => $q->withoutGlobalScopes()], 'items');
        $tenant = $this->document->tenant;
        $typeName = ucfirst($this->document->type);
        $amount = $tenant->currency . ' ' . number_format($this->document->total, 2);
        $due = $this->document->due_date?->format('d M Y') ?? '—';
        $payable = $tenant->pesapal_enabled && $this->document->balance_due > 0;

        // Semicolon-joined, not one bullet per line: this string can be sent either as free-form
        // text (real \n survives, WhatsApp renders it multi-line) OR as a template parameter —
        // and Meta's template API silently strips any \n from parameters (error #132018),
        // flattening a bulleted list into a single run-on-looking line. Semicolons degrade to a
        // clean single-line summary either way, instead of stray "•" characters mid-sentence.
        $items = $this->document->items->map(fn ($item) => "{$item->description} ("
            . number_format((float) $item->quantity, 2) . ' x ' . number_format((float) $item->price, 2)
            . ' = ' . number_format((float) $item->total, 2) . ')')->implode('; ');

        $lines = array_filter([
            "📄 *{$typeName} {$this->document->document_number}*",
            $tenant->name,
            $items !== '' ? "Vitu: {$items}" : null,
            "*Jumla: {$amount}*" . ($due !== '—' ? " (malipo: {$due})" : ''),
        ], fn ($line) => $line !== null);

        if ($payable) {
            $lines[] = 'Bonyeza kulipa: ' . $this->tenantPortalUrl($tenant, "/pay/{$this->document->id}");
        } else {
            $lines[] = $this->offlinePaymentMethodsText($tenant);
        }

        return implode("\n", $lines);
    }

    /** Same payment_methods JSON the tenant configures for the public pay page — bank AND mobile money, not just one bank account. */
    private function offlinePaymentMethodsText($tenant): string
    {
        $methods = collect($tenant->payment_methods ?? [])
            ->reject(fn ($m) => in_array($m['value'] ?? '', ['pesapal', 'cash', 'cheque'], true))
            ->map(function ($m) {
                $details = collect($m['details'] ?? [])->map(fn ($d) => "{$d['key']}: {$d['value']}")->implode(', ');
                return $details !== '' ? "{$m['label']} ({$details})" : null;
            })
            ->filter();

        if ($methods->isNotEmpty()) {
            return 'Njia za kulipa: ' . $methods->implode('; ');
        }

        $bank = trim(implode(', ', array_filter([
            $tenant->bank_name ? "{$tenant->bank_name}" : null,
            $tenant->bank_account_name,
            $tenant->bank_account_number,
        ])));

        return $bank !== '' ? "*Lipa kwa benki:* {$bank}" : 'Wasiliana nasi kwa maelezo ya malipo.';
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
