<?php

namespace App\Notifications;

use App\Channels\WhatsAppChannel;
use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * Tells a collector that a client paid an invoice assigned to them.
 *
 * $estimate (optional, all figures ESTIMATES until a supervisor verifies the target):
 *   ['target' => string, 'collected' => float, 'goal' => float, 'commission' => float]
 */
class InvoicePaymentOnAssignedNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    public function __construct(
        public Tenant $tenant,
        public string $clientName,
        public string $invoiceNumber,
        public float $amount,
        public float $balance,
        public ?array $estimate = null,
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

    private function money(float $v): string
    {
        return ($this->tenant->currency ?: 'TZS') . ' ' . number_format($v, 0);
    }

    public function message(): string
    {
        $rest = $this->balance <= 0
            ? 'imelipwa kikamilifu'
            : "deni lililobaki {$this->money($this->balance)}";

        return "Mteja {$this->clientName} amelipa {$this->money($this->amount)} kwenye {$this->invoiceNumber}; {$rest}";
    }

    public function estimateText(): ?string
    {
        if (!$this->estimate) {
            return null;
        }
        $e = $this->estimate;
        $text = "Lengo la makusanyo: umekusanya {$this->money($e['collected'])} kati ya {$this->money($e['goal'])}";
        if ($e['collected'] >= $e['goal']) {
            $text .= $e['commission'] > 0
                ? "; commission ya sasa ~{$this->money($e['commission'])} (makadirio, si commission ya mwisho)"
                : '; lengo limefikiwa (makadirio, si commission ya mwisho)';
        } else {
            $text .= "; bado {$this->money($e['goal'] - $e['collected'])} kufikia lengo (makadirio, si commission ya mwisho)";
        }

        return $text;
    }

    public function toWhatsApp($notifiable): string
    {
        $parts = [$this->message()];
        if ($est = $this->estimateText()) {
            $parts[] = $est;
        }

        return '*Malipo yamepokelewa*: ' . implode('; ', $parts) . " — {$this->tenant->name}";
    }

    public function toFcm($notifiable): ?array
    {
        return [
            'title' => 'Malipo kwenye invoice uliyopangiwa',
            'body'  => $this->message() . '.',
            'data'  => ['type' => 'followup_payment'],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        $mail = (new MailMessage)
            ->subject("Malipo: {$this->invoiceNumber} — {$this->tenant->name}")
            ->greeting("Habari {$notifiable->name},")
            ->line($this->message() . '.');
        if ($est = $this->estimateText()) {
            $mail->line($est . '.');
        }
        $mail->action('Fungua Makusanyo Yangu', url('/my-collections'));
        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toArray($notifiable): array
    {
        return [
            'type'    => 'followup_payment',
            'title'   => 'Malipo kwenye invoice uliyopangiwa',
            'message' => $this->message() . '.' . ($this->estimateText() ? ' ' . $this->estimateText() . '.' : ''),
            'url'     => '/my-collections',
        ];
    }
}
