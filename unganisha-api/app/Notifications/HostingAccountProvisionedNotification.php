<?php

namespace App\Notifications;

use App\Models\HostingAccount;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * WHMCS-style hosting "New Account Information" welcome email.
 *
 * Sent once right after createacct with the initial cPanel password (which is
 * NOT stored anywhere — sync send only, never queued). Also re-usable as a
 * "Resend Welcome Email" with $password = null, in which case the password
 * line is replaced with a note to use the existing password / reset it.
 */
class HostingAccountProvisionedNotification extends Notification
{
    use Queueable, HasTenantBranding;

    public function __construct(
        public HostingAccount $account,
        private ?string $password = null,
    ) {}

    public function via($notifiable): array
    {
        return ['mail'];
    }

    public function toMail($notifiable): MailMessage
    {
        $account = $this->account->loadMissing(['server', 'subscription.productService']);
        $tenant  = $account->tenant;
        $sub     = $account->subscription;
        $product = $sub?->productService;
        $server  = $account->server;

        $domain = $account->domain;
        $user   = $account->cpanel_username;
        $ip     = $account->meta['ip'] ?? ($server ? @gethostbyname($server->hostname) : null);
        $ns     = ($server?->nameservers && count($server->nameservers))
            ? $server->nameservers
            : config('hosting.default_nameservers', []);

        $money  = fn ($n) => $n === null ? null : 'Tsh.' . number_format((float) $n, 2) . 'TZS';
        $cycle  = [
            'monthly' => 'Monthly', 'quarterly' => 'Quarterly',
            'half_yearly' => 'Semi-Annually', 'yearly' => 'Annually', 'once' => 'One Time',
        ][$product?->billing_cycle] ?? ($product?->billing_cycle ?? '—');

        $firstPayment = $sub?->first_payment_amount;
        $recurring    = $sub?->recurring_amount ?? ($product ? (float) $product->price * (int) ($sub?->quantity ?? 1) : null);
        $nextDue      = $sub?->expire_date?->format('l, F jS, Y');

        $mail = (new MailMessage)
            ->subject("Your hosting account for {$domain} is ready")
            ->greeting("Dear {$notifiable->name},")
            ->line('**PLEASE READ THIS EMAIL IN FULL AND KEEP IT FOR YOUR RECORDS**')
            ->line('Thank you for your order! Your hosting account has now been set up and this email contains all the information you need to begin using it.')
            ->line('If you registered a domain name during signup, please note it will not be visible on the internet instantly — this is called propagation and can take up to 48 hours. Until it propagates, use the temporary URLs below.')
            ->line('---')
            ->line('**New Account Information**')
            ->line("Hosting Package: {$product?->name}")
            ->line("Domain: {$domain}");

        if ($firstPayment !== null) $mail->line("First Payment Amount: {$money($firstPayment)}");
        if ($recurring !== null)    $mail->line("Recurring Amount: {$money($recurring)}");
        $mail->line("Billing Cycle: {$cycle}");
        if ($nextDue) $mail->line("Next Due Date: {$nextDue}");

        $mail->line('---')
            ->line('**Login Details**')
            ->line("Username: {$user}");
        if ($this->password) {
            $mail->line("Password: {$this->password}")
                 ->line('_Please change this password after your first login — this is the only time it is sent._');
        } else {
            $mail->line('Password: use your existing cPanel password (reset it from your control panel, or ask us if needed).');
        }

        $cpanelHost = $ip ?: $server?->hostname;
        $mail->line("Control Panel URL: http://{$cpanelHost}:2082/")
            ->line("Once your domain has propagated you may also use http://www.{$domain}:2082/")
            ->line('---')
            ->line('**Server Information**')
            ->line("Server Name: {$server?->hostname}")
            ->line('Server IP: ' . ($ip ?: '—'));

        if (count($ns)) {
            $mail->line('If you are using an existing domain, point its nameservers to:');
            foreach ($ns as $i => $host) {
                $mail->line('Nameserver ' . ($i + 1) . ": {$host}");
            }
        }

        $mail->line('---')
            ->line('**Uploading Your Website**')
            ->line('Temporary FTP Hostname: ' . ($ip ?: $server?->hostname))
            ->line('Temporary Webpage URL: http://' . ($ip ?: $server?->hostname) . "/~{$user}/")
            ->line("Once propagated — FTP Hostname: {$domain} · Webpage: http://www.{$domain}")
            ->line('---')
            ->line('**Email Settings**')
            ->line("POP3 / SMTP Host: mail.{$domain}")
            ->line('Username: the full email address you are checking · Password: as set in your control panel')
            ->line('Thank you for choosing us.');

        return $this->applyBranding($mail, $tenant);
    }
}
