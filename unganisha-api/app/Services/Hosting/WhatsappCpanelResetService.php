<?php

namespace App\Services\Hosting;

use App\Models\Client;
use App\Models\HostingAccount;
use App\Models\ProvisioningLog;
use App\Models\Server;
use App\Models\Tenant;
use App\Models\WhatsappOtp;
use App\Notifications\HostingPasswordChangedNotification;
use App\Notifications\WhatsappOtpNotification;
use App\Services\WhmService;
use Illuminate\Support\Facades\Log;

/**
 * cPanel password reset for the WhatsApp bot: email one-time code, limits, strong generated password,
 * the same WHM "passwd" call and the same HostingPasswordChangedNotification the portal/staff use.
 * The new password is returned to the caller ONCE and is never stored, logged or audited.
 */
class WhatsappCpanelResetService
{
    public const OTP_MINUTES = 10;
    public const MAX_ATTEMPTS = 3;
    public const MAX_OTP_PER_HOUR = 3;
    public const MAX_RESETS_PER_DAY = 2;
    public const MAX_SUGGESTIONS = 4; // first suggestion + 3 regenerations
    public const AUDIT_ACTION = 'whatsapp.cpanel_password_reset';

    public static function purpose(HostingAccount $account): string
    {
        return 'cpanel_reset:' . $account->id;
    }

    public static function maskEmail(string $email): string
    {
        [$local, $domain] = array_pad(explode('@', $email, 2), 2, '');

        return mb_substr($local, 0, 1) . '***@' . $domain;
    }

    /**
     * Phone-friendly strong suggestion, e.g. "Kabuwe-Tezupa-Mudaha-4827#": three pronounceable words, 4 digits
     * and a symbol. 25 chars, upper+lower+digit+symbol, no ambiguous characters (0 O o-vs-0 1 l I), ~60+ bits.
     */
    public function generatePassword(): string
    {
        $cons = 'bdfghjkmnprstvwz';
        $vow = 'aeu';
        $pick = fn (string $set) => $set[random_int(0, strlen($set) - 1)];
        $words = [];
        for ($i = 0; $i < 3; $i++) {
            $w = '';
            for ($k = 0; $k < 3; $k++) {
                $w .= $pick($cons) . $pick($vow);
            }
            $words[] = ucfirst($w);
        }
        $digits = '';
        for ($i = 0; $i < 4; $i++) {
            $digits .= $pick('23456789');
        }

        return implode('-', $words) . '-' . $digits . $pick('#@%*+');
    }

    private function hash(string $code, string $phone): string
    {
        return hash_hmac('sha256', $code . '|' . $phone, (string) config('app.key'));
    }

    /** @return string 'sent'|'no_email'|'rate_limited'|'mail_failed' */
    public function requestOtp(Tenant $tenant, Client $client, string $phone, HostingAccount $account): string
    {
        if (!$client->email) {
            return 'no_email';
        }
        $recent = WhatsappOtp::where('client_id', $client->id)->where('created_at', '>=', now()->subHour())->count();
        if ($recent >= self::MAX_OTP_PER_HOUR) {
            return 'rate_limited';
        }

        $purpose = self::purpose($account);
        WhatsappOtp::where('tenant_id', $tenant->id)->where('phone', $phone)->where('purpose', $purpose)
            ->whereNull('used_at')->update(['used_at' => now()]);

        $code = str_pad((string) random_int(0, 999999), 6, '0', STR_PAD_LEFT);
        $otp = WhatsappOtp::create([
            'tenant_id' => $tenant->id, 'phone' => $phone, 'client_id' => $client->id, 'purpose' => $purpose,
            'code_hash' => $this->hash($code, $phone), 'attempts' => 0, 'expires_at' => now()->addMinutes(self::OTP_MINUTES),
        ]);

        try {
            $client->notify(new WhatsappOtpNotification($tenant, $code, $account->domain, self::OTP_MINUTES));
        } catch (\Throwable $e) {
            Log::warning('WhatsApp OTP email failed', ['client_id' => $client->id, 'hosting_account_id' => $account->id]);
            $otp->delete();

            return 'mail_failed';
        }

        return 'sent';
    }

    /** @return string 'ok'|'wrong'|'exhausted'|'expired' */
    public function verifyOtp(Tenant $tenant, Client $client, string $phone, HostingAccount $account, string $input): string
    {
        $otp = WhatsappOtp::where('tenant_id', $tenant->id)->where('phone', $phone)->where('client_id', $client->id)
            ->where('purpose', self::purpose($account))->whereNull('used_at')->latest('id')->first();
        if (!$otp || $otp->expires_at->isPast() || $otp->attempts >= self::MAX_ATTEMPTS) {
            return 'expired';
        }

        $otp->attempts++;
        if (hash_equals($otp->code_hash, $this->hash(trim($input), $phone))) {
            $otp->used_at = now();
            $otp->save();

            return 'ok';
        }
        if ($otp->attempts >= self::MAX_ATTEMPTS) {
            $otp->used_at = now();
            $otp->save();

            return 'exhausted';
        }
        $otp->save();

        return 'wrong';
    }

    public function cancelOtps(Tenant $tenant, string $phone): void
    {
        WhatsappOtp::where('tenant_id', $tenant->id)->where('phone', $phone)->whereNull('used_at')->update(['used_at' => now()]);
    }

    public function resetsInLastDay(HostingAccount $account): int
    {
        return ProvisioningLog::withoutGlobalScopes()->where('hosting_account_id', $account->id)
            ->where('action', self::AUDIT_ACTION)->where('status', 'success')->where('created_at', '>=', now()->subDay())->count();
    }

    /**
     * Sets the given (server-generated, client-approved) password through WHM: exactly one WHM call. Throws on
     * WHM failure (nothing changed). Audits (no password) and sends the standard security alert.
     */
    public function applyPassword(Tenant $tenant, Client $client, HostingAccount $account, string $password): void
    {
        $server = Server::withoutGlobalScopes()->find($account->server_id);
        if (!$server || !$account->cpanel_username) {
            throw new \RuntimeException('Hosting account is not linked to a server');
        }

        (new WhmService($server))->forAccount($account->id)->resetPassword($account->cpanel_username, $password);

        try {
            ProvisioningLog::withoutGlobalScopes()->create([
                'tenant_id' => $tenant->id, 'hosting_account_id' => $account->id, 'server_id' => $server->id,
                'action' => self::AUDIT_ACTION, 'request' => ['client_id' => $client->id, 'channel' => 'whatsapp'], 'status' => 'success',
            ]);
        } catch (\Throwable $e) {
            Log::warning('WhatsApp cPanel reset audit failed', ['hosting_account_id' => $account->id]);
        }

        try {
            if ($client->email || $client->phone) {
                $client->notify(new HostingPasswordChangedNotification($account, $tenant, 'WhatsApp chat'));
            }
        } catch (\Throwable $e) {
            Log::warning('Password-change notice failed', ['error' => $e->getMessage()]);
        }

    }
}
