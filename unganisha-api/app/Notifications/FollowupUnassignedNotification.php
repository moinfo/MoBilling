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
 * Sent to a staff member when an invoice previously assigned to them is reassigned to someone else
 * (FollowupController::reassign). Never sent when they reassign to themselves, or when nobody was
 * previously assigned — small counterpart to FollowupAssignedNotification, which still goes to the new
 * assignee on every reassignment.
 */
class FollowupUnassignedNotification extends Notification implements ShouldQueue
{
    use Queueable, HasTenantBranding;

    public function __construct(
        public Tenant $tenant,
        public string $reassignerName,
        public string $clientName,
        public string $invoiceNumber,
        public string $newAssigneeName,
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
        return "{$this->clientName} - {$this->invoiceNumber} imehamishiwa kwa {$this->newAssigneeName}";
    }

    public function toWhatsApp($notifiable): string
    {
        return "*Umeondolewa kwenye deni*: {$this->summary()} (na {$this->reassignerName}) — {$this->tenant->name}";
    }

    public function toFcm($notifiable): ?array
    {
        return [
            'title' => 'Umeondolewa kwenye ufuatiliaji',
            'body'  => $this->summary() . '.',
            'data'  => ['type' => 'followup_unassigned'],
        ];
    }

    public function toMail($notifiable): MailMessage
    {
        $mail = (new MailMessage)
            ->subject("Umeondolewa kwenye ufuatiliaji — {$this->invoiceNumber}")
            ->greeting("Habari {$notifiable->name},")
            ->line("{$this->reassignerName}: {$this->summary()}.")
            ->action('Fungua Follow-ups', url('/followups'));
        $this->applyBranding($mail, $this->tenant);

        return $mail;
    }

    public function toArray($notifiable): array
    {
        return [
            'type'    => 'followup_unassigned',
            'title'   => 'Umeondolewa kwenye ufuatiliaji',
            'message' => $this->summary() . '.',
            'url'     => '/followups',
        ];
    }
}
