<?php

namespace App\Notifications;

use App\Channels\SmsChannel;
use App\Channels\WhatsAppChannel;
use App\Models\Document;
use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use App\Services\PdfService;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class RecurringInvoiceReminderNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    public ?string $forceChannels = null;

    public function __construct(
        public Document $document,
        public Tenant $tenant,
        public int $daysRemaining,
    ) {}

    public function via($notifiable): array
    {
        // Manual reminder — use the specified channel(s), but still respect master switches
        if ($this->forceChannels) {
            $channels = [];
            if (in_array($this->forceChannels, ['email', 'both']) && $this->tenant->email_enabled) {
                $channels[] = 'mail';
            }
            if (in_array($this->forceChannels, ['sms', 'both']) && $this->tenant->sms_enabled) {
                $channels[] = SmsChannel::class;
            }
            if (in_array($this->forceChannels, ['whatsapp', 'both']) && $this->tenant->whatsapp_enabled) {
                $channels[] = WhatsAppChannel::class;
            }
            // Mobile push: FcmChannel no-ops when FCM_CREDENTIALS is unset and
            // when the client has no registered devices, so it is always safe on.
            $channels[] = \App\Channels\FcmChannel::class;
            return $channels;
        }

        // Automated — respect tenant settings
        $channels = [];

        if ($this->tenant->email_enabled && $this->tenant->reminder_email_enabled) {
            $channels[] = 'mail';
        }

        if ($this->tenant->sms_enabled && $this->tenant->reminder_sms_enabled) {
            $channels[] = SmsChannel::class;
        }

        if ($this->tenant->whatsapp_enabled && $this->tenant->reminder_whatsapp_enabled) {
            $channels[] = WhatsAppChannel::class;
        }

        // Mobile push: FcmChannel no-ops when FCM_CREDENTIALS is unset and
        // when the client has no registered devices, so it is always safe on.
        $channels[] = \App\Channels\FcmChannel::class;

        return $channels;
    }

    public function toFcm($notifiable): ?array
    {
        $currency = $this->tenant->currency;

        return [
            'title' => "Invoice {$this->document->document_number} due in {$this->daysRemaining} day(s)",
            'body'  => "Amount due: {$currency} " . number_format((float) $this->document->balance_due, 2)
                . " — due {$this->document->due_date->format('d M Y')}.",
            'data'  => ['type' => 'invoice', 'document_id' => $this->document->id],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        $this->document->loadMissing('items', 'client');
        $this->document->loadMissing(['tenant' => fn ($q) => $q->withoutGlobalScopes()]);

        $doc      = $this->document;
        $client   = $doc->client;
        $currency = $this->tenant->currency;
        $money    = fn ($n) => $currency . ' ' . number_format((float) $n, 2);
        $genDate  = $doc->date?->format('l, F jS, Y');
        $dueDate  = $doc->due_date->format('l, F jS, Y');

        $subject = "Reminder: Invoice {$doc->document_number} due in {$this->daysRemaining} day(s) — {$this->tenant->name}";

        $pdf = app(PdfService::class)->generate($doc);
        $pdfContent = $pdf->output();

        $greetingName = $this->properCase($client->name)
            . ($client->tax_id ? " (TIN: {$client->tax_id})" : '');

        $mail = (new MailMessage)
            ->subject($subject)
            ->greeting("Dear {$greetingName},")
            ->line("This is a billing reminder that your invoice no. {$doc->document_number}"
                . ($genDate ? " which was generated on {$genDate}" : '') . " is due on {$dueDate}.")
            ->line('---')
            ->line('**Invoice Summary**')
            ->line("Invoice: {$doc->document_number}")
            ->line('Amount Due: ' . $money($doc->balance_due))
            ->line("Due Date: {$dueDate}")
            ->line('---')
            ->line('**Invoice Items**');

        foreach ($doc->items as $item) {
            $mail->line("{$item->description} — " . $money($item->total));
        }

        $mail->line('------------------------------------------------------')
            ->line('Sub Total: ' . $money($doc->subtotal));
        if ((float) $doc->discount_amount > 0) {
            $mail->line('Discount: -' . $money($doc->discount_amount));
        }
        if ((float) $doc->tax_amount > 0) {
            $mail->line('Tax: ' . $money($doc->tax_amount));
        }
        $mail->line('Total: ' . $money($doc->total))
            ->line('---');

        // Add "Pay Now" button if tenant has Pesapal enabled and invoice has balance
        if ($this->tenant->pesapal_enabled && $doc->balance_due > 0) {
            $payUrl = $this->tenantPortalUrl($doc->tenant, "/pay/{$doc->id}");
            $mail->action('Pay Now', $payUrl);
        }

        // Only warn about suspension if it's actually going to happen — a
        // static threat would be false while a tenant has auto-suspend off.
        if ($this->tenant->auto_suspend_enabled) {
            $mail->line("Please note that if this invoice is not paid by {$dueDate}, your service may be suspended.");
        }

        $mail->line('Thank you for your business.')
            ->attachData($pdfContent, "{$doc->document_number}.pdf", [
                'mime' => 'application/pdf',
            ]);

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toSms($notifiable): ?string
    {
        $currency = $this->tenant->currency;
        $amount = number_format($this->document->total, 2);
        $dueDate = $this->document->due_date->format('d M Y');

        $msg = "Reminder: Invoice {$this->document->document_number} for {$currency} {$amount} is due on {$dueDate} ({$this->daysRemaining} day(s) remaining). — {$this->tenant->name}";

        if ($this->tenant->pesapal_enabled && $this->document->balance_due > 0) {
            $payUrl = $this->tenantPortalUrl($this->document->tenant, "/pay/{$this->document->id}");
            $msg .= " Pay: {$payUrl}";
        }

        return $msg;
    }

    public function toWhatsApp($notifiable): array
    {
        $currency = $this->tenant->currency;
        $amount = "{$currency} " . number_format($this->document->total, 2);
        $balanceDue = "{$currency} " . number_format($this->document->balance_due, 2);
        $dueDate = $this->document->due_date->format('d M Y');
        $params = [$this->document->document_number, $amount, $balanceDue, $dueDate, $this->tenant->name];
        $payable = $this->tenant->pesapal_enabled && $this->document->balance_due > 0;

        return array_filter([
            'template' => $payable ? 'invoice_reminder_v2' : 'invoice_reminder_v1',
            'parameters' => $params,
            'language' => 'en',
            'button_url' => $payable ? (string) $this->document->id : null,
            'fallback' => "📋 Invoice Reminder: {$this->document->document_number}, balance {$balanceDue}, due {$dueDate}."
                . ($payable ? ' Pay online: ' . $this->tenantPortalUrl($this->tenant, "/pay/{$this->document->id}") : '')
                . " — {$this->tenant->name}",
        ], fn ($v) => $v !== null);
    }
}
