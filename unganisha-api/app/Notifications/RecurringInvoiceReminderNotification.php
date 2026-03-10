<?php

namespace App\Notifications;

use App\Channels\SmsChannel;
use App\Channels\WhatsAppChannel;
use App\Models\Document;
use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use App\Services\PdfService;
use App\Services\ReminderTemplateService;
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

        return $channels;
    }

    public function toMail($notifiable): MailMessage
    {
        $this->document->loadMissing('items', 'client');
        $this->document->loadMissing(['tenant' => fn ($q) => $q->withoutGlobalScopes()]);

        $renderer = app(ReminderTemplateService::class);
        $currency = $this->tenant->currency;
        $amount = number_format($this->document->total, 2);
        $dueDate = $this->document->due_date->format('d M Y');

        $subject = "Reminder: Invoice {$this->document->document_number} due in {$this->daysRemaining} day(s) — {$this->tenant->name}";

        $pdf = app(PdfService::class)->generate($this->document);
        $pdfContent = $pdf->output();

        $mail = (new MailMessage)
            ->subject($subject)
            ->greeting("Hello {$this->document->client->name},")
            ->line("This is a friendly reminder that invoice {$this->document->document_number} for {$currency} {$amount} is due on {$dueDate}.")
            ->line("Please ensure payment is made before the due date to avoid any disruption.");

        // Add "Pay Now" button if tenant has Pesapal enabled and invoice has balance
        if ($this->tenant->pesapal_enabled && $this->document->balance_due > 0) {
            $payUrl = config('app.frontend_url', 'https://mobilling.co.tz') . "/pay/{$this->document->id}";
            $mail->action('Pay Now', $payUrl);
        }

        $mail->line('Thank you for your business.')
            ->attachData($pdfContent, "{$this->document->document_number}.pdf", [
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
            $payUrl = config('app.frontend_url', 'https://mobilling.co.tz') . "/pay/{$this->document->id}";
            $msg .= " Pay: {$payUrl}";
        }

        return $msg;
    }

    public function toWhatsApp($notifiable): ?string
    {
        $currency = $this->tenant->currency;
        $amount = number_format($this->document->total, 2);
        $dueDate = $this->document->due_date->format('d M Y');
        $balanceDue = number_format($this->document->balance_due, 2);

        $msg = "📋 *Invoice Reminder*\n\n"
            . "*{$this->document->document_number}*\n"
            . "Amount: *{$currency} {$amount}*\n"
            . "Balance Due: *{$currency} {$balanceDue}*\n"
            . "Due Date: {$dueDate}\n";

        if ($this->daysRemaining > 0) {
            $msg .= "⏳ {$this->daysRemaining} day(s) remaining\n";
        } elseif ($this->daysRemaining === 0) {
            $msg .= "⚠️ *Due today*\n";
        } else {
            $msg .= "🔴 *" . abs($this->daysRemaining) . " day(s) overdue*\n";
        }

        if ($this->tenant->pesapal_enabled && $this->document->balance_due > 0) {
            $payUrl = config('app.frontend_url', 'https://mobilling.co.tz') . "/pay/{$this->document->id}";
            $msg .= "\n💳 Pay online: {$payUrl}";
        }

        $msg .= "\n\n— {$this->tenant->name}";

        return $msg;
    }
}
