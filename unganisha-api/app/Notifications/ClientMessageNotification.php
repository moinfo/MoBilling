<?php

namespace App\Notifications;

use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/** Free-form message an admin sends to a client from the admin area. */
class ClientMessageNotification extends Notification
{
    use Queueable, HasTenantBranding;

    public function __construct(
        public Tenant $tenant,
        public string $subjectLine,
        public string $body,
    ) {}

    public function via($notifiable): array
    {
        return ['mail'];
    }

    public function toMail($notifiable): MailMessage
    {
        $mail = (new MailMessage)
            ->subject($this->subjectLine)
            ->greeting("Dear {$notifiable->name},");

        // Preserve the admin's line breaks as separate paragraphs.
        foreach (preg_split('/\n{2,}/', trim($this->body)) as $para) {
            $mail->line(trim($para));
        }

        return $this->applyBranding($mail, $this->tenant);
    }
}
