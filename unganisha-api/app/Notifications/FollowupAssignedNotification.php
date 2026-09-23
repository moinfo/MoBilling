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
 * Sent to a staff member when invoices are assigned to them for debt collection.
 * One notification covers a whole (bulk) assignment.
 *
 * $items: list of ['client' => string, 'invoice' => string, 'balance' => float, 'next' => 'd M Y'].
 * $count / $totalBalance describe the FULL assignment even when $items is truncated.
 */
class FollowupAssignedNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    private const MAX_LISTED = 5;

    public function __construct(
        public Tenant $tenant,
        public string $assignerName,
        public array $items,
        public int $count,
        public float $totalBalance,
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

    private function line(array $i): string
    {
        return "{$i['client']} - {$i['invoice']} - deni {$this->money((float) $i['balance'])} - fuatilia {$i['next']}";
    }

    public function summary(): string
    {
        return $this->count === 1
            ? "Umepangiwa invoice {$this->items[0]['invoice']}, jumla ya deni {$this->money($this->totalBalance)}"
            : "Umepangiwa invoice {$this->count}, jumla ya deni {$this->money($this->totalBalance)}";
    }

    private function listed(): array
    {
        return array_map(fn ($i) => $this->line($i), array_slice($this->items, 0, self::MAX_LISTED));
    }

    private function more(): int
    {
        return max($this->count - min(count($this->items), self::MAX_LISTED), 0);
    }

    public function toWhatsApp($notifiable): string
    {
        // Semicolon-joined so the body survives newline-stripping paths.
        $parts = $this->listed();
        if ($this->more() > 0) {
            $parts[] = "+{$this->more()} zaidi";
        }

        return "*Ukusanyaji wa madeni*: {$this->summary()}; " . implode('; ', array_map(fn ($p) => "• $p", $parts))
            . " — {$this->tenant->name}";
    }

    public function toFcm($notifiable): ?array
    {
        return [
            'title' => 'Umepangiwa madeni ya kufuatilia',
            'body'  => $this->summary() . '.',
            'data'  => ['type' => 'followup_assigned'],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        $mail = (new MailMessage)
            ->subject("Umepangiwa madeni ya kufuatilia — {$this->tenant->name}")
            ->greeting("Habari {$notifiable->name},")
            ->line("{$this->assignerName}: {$this->summary()}.");
        foreach ($this->listed() as $l) {
            $mail->line("• $l");
        }
        if ($this->more() > 0) {
            $mail->line("+{$this->more()} zaidi");
        }
        $mail->action('Fungua Makusanyo Yangu', url('/my-collections'));
        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toArray($notifiable): array
    {
        return [
            'type'    => 'followup_assigned',
            'title'   => 'Umepangiwa madeni ya kufuatilia',
            'message' => $this->summary() . '.',
            'url'     => '/my-collections',
        ];
    }
}
