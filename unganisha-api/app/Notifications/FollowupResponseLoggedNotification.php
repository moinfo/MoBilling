<?php

namespace App\Notifications;

use App\Models\Tenant;
use App\Channels\WhatsAppChannel;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * Sent to the person who assigned an invoice for collection (CollectionAssignment::assigned_by), or —
 * when that can't be determined — to tenant users with documents.approve_collection, whenever a staff
 * member other than the recipient logs a follow-up call. Never sent to the caller themselves.
 */
class FollowupResponseLoggedNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    private const OUTCOME_LABELS = [
        'promised' => 'Ameahidi kulipa',
        'declined' => 'Amekataa kulipa',
        'no_answer' => 'Hakupokea simu',
        'disputed' => 'Anapinga deni',
        'partial_payment' => 'Atalipa kiasi',
    ];

    public function __construct(
        public Tenant $tenant,
        public string $staffName,
        public string $clientName,
        public string $invoiceNumber,
        public string $outcome,
        public string $notes,
        public ?string $promiseDate,
        public ?float $promiseAmount,
        public bool $escalated,
    ) {}

    public function via($notifiable): array
    {
        $channels = ['database'];
        if ($this->tenant->email_enabled && $notifiable->email) {
            $channels[] = 'mail';
        }
        if ($this->tenant->whatsapp_enabled && $notifiable->phone) {
            $channels[] = WhatsAppChannel::class;
        }
        $channels[] = \App\Channels\FcmChannel::class;

        return $channels;
    }

    private function outcomeLabel(): string
    {
        return self::OUTCOME_LABELS[$this->outcome] ?? $this->outcome;
    }

    public function summary(): string
    {
        $s = "{$this->staffName} amepiga simu {$this->clientName} - {$this->invoiceNumber}: {$this->outcomeLabel()}";
        if ($this->promiseDate) {
            $s .= " (ataahidi {$this->promiseDate})";
        }
        if ($this->escalated) {
            $s .= ' — IMEFIKIA KIKOMO cha simu 3, inahitaji hatua zaidi';
        }

        return $s;
    }

    public function toWhatsApp($notifiable): string
    {
        return "*Majibu ya mfuatiliaji*: {$this->summary()}. Maelezo: {$this->notes} — {$this->tenant->name}";
    }

    public function toFcm($notifiable): ?array
    {
        return [
            'title' => 'Mfuatiliaji amejibu',
            'body'  => $this->summary() . '.',
            'data'  => ['type' => 'followup_response_logged'],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        $mail = (new MailMessage)
            ->subject("Mfuatiliaji amejibu — {$this->invoiceNumber}")
            ->greeting("Habari {$notifiable->name},")
            ->line($this->summary() . '.')
            ->line("Maelezo: {$this->notes}")
            ->action('Fungua Follow-ups', url('/followups'));
        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toArray($notifiable): array
    {
        return [
            'type'    => 'followup_response_logged',
            'title'   => 'Mfuatiliaji amejibu',
            'message' => $this->summary() . '.',
            'url'     => '/followups',
        ];
    }
}
