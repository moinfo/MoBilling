<?php

namespace App\Notifications;

use App\Channels\SmsChannel;
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
        // Manual reminder — use the specified channel(s)
        if ($this->forceChannels) {
            return match ($this->forceChannels) {
                'email' => ['mail'],
                'sms' => [SmsChannel::class],
                'both' => ['mail', SmsChannel::class],
                default => ['mail'],
            };
        }

        // Automated — respect tenant settings
        $channels = [];

        if ($this->tenant->reminder_email_enabled) {
            $channels[] = 'mail';
        }

        if ($this->tenant->sms_enabled && $this->tenant->reminder_sms_enabled) {
            $channels[] = SmsChannel::class;
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
            ->line("Please ensure payment is made before the due date to avoid any disruption.")
            ->line('Thank you for your business.')
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

        return "Reminder: Invoice {$this->document->document_number} for {$currency} {$amount} is due on {$dueDate} ({$this->daysRemaining} day(s) remaining). — {$this->tenant->name}";
    }
}
