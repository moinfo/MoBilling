<?php

namespace App\Notifications;

use App\Models\ResellerApplication;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/** Tells the applying client their reseller application was approved or rejected — neutral, professional wording. */
class ResellerApplicationDecidedNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(public ResellerApplication $application) {}

    public function via($notifiable): array
    {
        return ['mail', 'database'];
    }

    public function toMail($notifiable): MailMessage
    {
        if ($this->application->status === 'approved') {
            return (new MailMessage)
                ->subject('Your reseller application has been approved')
                ->greeting("Hello {$this->application->contact_name},")
                ->line("Your application to become a white-label reseller under the brand \"{$this->application->brand_name}\" has been approved.")
                ->line('Our team will set up your reseller account and be in touch with next steps shortly.');
        }

        $mail = (new MailMessage)
            ->subject('Update on your reseller application')
            ->greeting("Hello {$this->application->contact_name},")
            ->line("We've reviewed your application to become a white-label reseller under the brand \"{$this->application->brand_name}\" and are unable to proceed with it at this time.");

        if ($this->application->staff_note) {
            $mail->line('Reason: ' . $this->application->staff_note);
        }

        return $mail->line('If you have questions, please get in touch with us.');
    }

    public function toArray($notifiable): array
    {
        return [
            'type'           => 'reseller_application_decided',
            'title'          => $this->application->status === 'approved' ? 'Reseller application approved' : 'Reseller application update',
            'message'        => $this->application->status === 'approved'
                ? "Your application for \"{$this->application->brand_name}\" was approved."
                : "Your application for \"{$this->application->brand_name}\" was not approved.",
            'application_id' => $this->application->id,
        ];
    }
}
