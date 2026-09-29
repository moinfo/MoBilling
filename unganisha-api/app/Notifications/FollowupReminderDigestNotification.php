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
 * One daily digest per staff member (followups:remind-staff) listing THEIR follow-up calls due today
 * and overdue — a reminder to actually make the calls, not a per-row spam of notifications.
 *
 * $items: up to 5 ['client' => string, 'invoice' => string, 'due' => 'YYYY-MM-DD'].
 * $dueTodayCount / $overdueCount describe the full set even when $items is truncated.
 */
class FollowupReminderDigestNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    private const MAX_LISTED = 5;

    public function __construct(
        public Tenant $tenant,
        public array $items,
        public int $dueTodayCount,
        public int $overdueCount,
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

    public function summary(): string
    {
        $parts = [];
        if ($this->dueTodayCount > 0) {
            $parts[] = "{$this->dueTodayCount} leo";
        }
        if ($this->overdueCount > 0) {
            $parts[] = "{$this->overdueCount} zimechelewa";
        }

        return 'Simu za kufuatilia: ' . implode(', ', $parts);
    }

    private function line(array $i): string
    {
        return "{$i['client']} - {$i['invoice']} (tarehe {$i['due']})";
    }

    private function listed(): array
    {
        return array_map(fn ($i) => $this->line($i), array_slice($this->items, 0, self::MAX_LISTED));
    }

    private function more(): int
    {
        return max(($this->dueTodayCount + $this->overdueCount) - min(count($this->items), self::MAX_LISTED), 0);
    }

    public function toWhatsApp($notifiable): string
    {
        $parts = $this->listed();
        if ($this->more() > 0) {
            $parts[] = "+{$this->more()} zaidi";
        }

        return "*{$this->summary()}*: " . implode('; ', array_map(fn ($p) => "• $p", $parts)) . " — {$this->tenant->name}";
    }

    public function toFcm($notifiable): ?array
    {
        return [
            'title' => 'Kumbusho la simu za kufuatilia',
            'body'  => $this->summary() . '.',
            'data'  => ['type' => 'followup_reminder_digest'],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        $mail = (new MailMessage)
            ->subject("Kumbusho la simu za kufuatilia — {$this->tenant->name}")
            ->greeting("Habari {$notifiable->name},")
            ->line($this->summary() . '.');
        foreach ($this->listed() as $l) {
            $mail->line("• $l");
        }
        if ($this->more() > 0) {
            $mail->line("+{$this->more()} zaidi");
        }
        $mail->action('Fungua Follow-ups Zangu', url('/followups'));
        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toArray($notifiable): array
    {
        return [
            'type'    => 'followup_reminder_digest',
            'title'   => 'Kumbusho la simu za kufuatilia',
            'message' => $this->summary() . '.',
            'url'     => '/followups',
        ];
    }
}
