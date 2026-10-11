<?php

namespace App\Notifications;

use App\Channels\SmsChannel;
use App\Channels\WhatsAppChannel;
use App\Models\LinodeResource;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * VPS "New Server Information" welcome email — sent once, right after
 * creation, with the root password (NOT stored anywhere; sync send only).
 */
class LinodeVpsProvisionedNotification extends Notification
{
    use Queueable, HasTenantBranding;

    public function __construct(
        public LinodeResource $resource,
        private string $rootPassword,
    ) {}

    public function via($notifiable): array
    {
        $tenant = $this->resource->tenant;

        $channels = [];
        if (($tenant?->email_enabled ?? true) && $notifiable->email) {
            $channels[] = 'mail';
        }
        if ($tenant?->sms_enabled && $notifiable->phone) {
            $channels[] = SmsChannel::class;
        }
        if ($tenant?->whatsapp_enabled && $notifiable->phone) {
            $channels[] = WhatsAppChannel::class;
        }
        $channels[] = \App\Channels\FcmChannel::class;

        return $channels;
    }

    private function ip(): ?string
    {
        return $this->resource->ipv4[0] ?? null;
    }

    public function toFcm($notifiable): ?array
    {
        return [
            'title' => "Your VPS ({$this->resource->label}) is ready",
            'body'  => 'Login details were sent to your email.',
            'data'  => ['type' => 'linode_vps', 'linode_resource_id' => $this->resource->id],
        ];
    }

    /** Never includes the password — that goes by email only. */
    public function toSms($notifiable): ?string
    {
        $tenant = $this->resource->tenant;

        return "VPS yako ({$this->resource->label}, IP: {$this->ip()}) iko tayari! Maelezo kamili (na root password) yametumwa kwenye email yako. — " . ($tenant?->name ?? 'MoBilling');
    }

    public function toWhatsApp($notifiable): ?string
    {
        $tenant = $this->resource->tenant;

        return "🎉 VPS yako ({$this->resource->label}, IP: {$this->ip()}) iko tayari! Maelezo kamili (na root password) yametumwa kwenye email yako. — " . ($tenant?->name ?? 'MoBilling');
    }

    public function toMail($notifiable): MailMessage
    {
        $tenant = $this->resource->tenant;

        $mail = (new MailMessage)
            ->subject("Your VPS ({$this->resource->label}) is ready")
            ->greeting("Dear {$this->properCase($notifiable->name)},")
            ->line('**PLEASE READ THIS EMAIL IN FULL AND PRINT IT FOR YOUR RECORDS**')
            ->line('Thank you for your order! Your VPS has now been set up and this email contains all the information you need to begin using it.')
            ->line('---')
            ->line('**Server Information**')
            ->line("Label: {$this->resource->label}")
            ->line('IP Address: ' . ($this->ip() ?: '—'))
            ->line('Region: ' . ($this->resource->region ?: '—'))
            ->line('Plan: ' . ($this->resource->plan ?: '—'))
            ->line('---')
            ->line('**Login Details**')
            ->line('Username: root')
            ->line("Password: {$this->rootPassword}")
            ->line('_Please change this password after your first login — this is the only time it is sent._')
            ->line("SSH: ssh root@{$this->ip()}")
            ->line('---')
            ->line('Thank you for choosing us.');

        return $this->applyBranding($mail, $tenant);
    }
}
