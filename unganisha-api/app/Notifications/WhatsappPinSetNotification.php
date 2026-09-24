<?php

namespace App\Notifications;

use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/** Security notice to a staff member: a WhatsApp staff-assist PIN was just created for their account. */
class WhatsappPinSetNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function via($notifiable): array
    {
        return ['database', 'mail'];
    }

    public function toMail($notifiable): MailMessage
    {
        return (new MailMessage)
            ->subject('PIN ya WhatsApp imewekwa / WhatsApp PIN set')
            ->line('PIN ya WhatsApp (staff-assist) imewekwa kwenye akaunti yako. Kama si wewe, wasiliana na msimamizi mara moja.')
            ->line('A WhatsApp staff-assist PIN was just set on your account. If this was not you, contact your administrator immediately.');
    }

    public function toArray($notifiable): array
    {
        return [
            'type' => 'whatsapp_pin_set',
            'title' => 'PIN ya WhatsApp imewekwa',
            'message' => 'PIN ya WhatsApp (staff-assist) imewekwa kwenye akaunti yako. Kama si wewe, wasiliana na msimamizi. / A WhatsApp staff-assist PIN was set on your account. If this was not you, contact your administrator.',
            'url' => '/',
        ];
    }
}
