<?php

namespace App\Notifications;

use App\Channels\SmsChannel;
use App\Channels\WhatsAppChannel;
use App\Models\Document;
use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use App\Services\PdfService;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;
use Illuminate\Support\Collection;

class BundledReminderNotification extends Notification
{
    use Queueable, HasTenantBranding;

    public ?string $forceChannels = null;

    /** @var Collection<int, Document> */
    public Collection $documents;

    public function __construct(
        Collection $documents,
        public Tenant $tenant,
    ) {
        $this->documents = $documents;
    }

    public function via($notifiable): array
    {
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
        $currency = $this->tenant->currency;
        $clientName = $notifiable->name;
        $count = $this->documents->count();
        $totalBalance = $this->documents->sum('balance_due');

        $subject = "Payment Reminder: {$count} unpaid invoice(s) totaling {$currency} "
            . number_format($totalBalance, 2) . " — {$this->tenant->name}";

        $mail = (new MailMessage)
            ->subject($subject)
            ->greeting("Hello {$clientName},")
            ->line("This is a friendly reminder that you have **{$count} unpaid invoice(s)** with a total balance of **{$currency} " . number_format($totalBalance, 2) . "**.")
            ->line('Here is a summary of your outstanding invoices:')
            ->line('---');

        foreach ($this->documents as $doc) {
            $dueLabel = $doc->due_date ? $doc->due_date->format('d M Y') : 'N/A';
            $balanceFormatted = number_format($doc->balance_due, 2);
            $status = $doc->due_date && $doc->due_date->isPast() ? ' (OVERDUE)' : '';
            $mail->line("**{$doc->document_number}** — {$currency} {$balanceFormatted} — Due: {$dueLabel}{$status}");
        }

        $mail->line('---')
            ->line("**Total Balance Due: {$currency} " . number_format($totalBalance, 2) . "**")
            ->line('Please ensure payment is made to avoid any disruption to your services.');

        // Attach all PDFs
        $pdfService = app(PdfService::class);
        foreach ($this->documents as $doc) {
            $doc->loadMissing('items', 'client');
            $pdf = $pdfService->generate($doc);
            $mail->attachData($pdf->output(), "{$doc->document_number}.pdf", [
                'mime' => 'application/pdf',
            ]);
        }

        $mail->line('Thank you for your business.');

        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toSms($notifiable): ?string
    {
        $currency = $this->tenant->currency;
        $count = $this->documents->count();
        $totalBalance = $this->documents->sum('balance_due');
        $invoiceNumbers = $this->documents->pluck('document_number')->join(', ');

        $msg = "Reminder: You have {$count} unpaid invoice(s) totaling {$currency} "
            . number_format($totalBalance, 2) . ". "
            . "Invoices: {$invoiceNumbers}. "
            . "— {$this->tenant->name}";

        return $msg;
    }

    public function toWhatsApp($notifiable): ?string
    {
        $currency = $this->tenant->currency;
        $count = $this->documents->count();
        $totalBalance = $this->documents->sum('balance_due');

        $lines = [
            "📋 *Payment Reminder*",
            "",
            "You have *{$count} unpaid invoice(s)* with a total balance of *{$currency} " . number_format($totalBalance, 2) . "*.",
            "",
            "*Outstanding Invoices:*",
        ];

        foreach ($this->documents as $doc) {
            $dueLabel = $doc->due_date ? $doc->due_date->format('d M Y') : 'N/A';
            $balanceFormatted = number_format($doc->balance_due, 2);
            $overdue = $doc->due_date && $doc->due_date->isPast() ? ' 🔴' : '';
            $lines[] = "  ▸ {$doc->document_number} — {$currency} {$balanceFormatted} — Due: {$dueLabel}{$overdue}";
        }

        $lines[] = "";
        $lines[] = "💰 *Total: {$currency} " . number_format($totalBalance, 2) . "*";
        $lines[] = "";
        $lines[] = "Please make payment at your earliest convenience.";
        $lines[] = "";
        $lines[] = "— {$this->tenant->name}";

        return implode("\n", $lines);
    }
}
