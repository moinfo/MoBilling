<?php

namespace App\Services\Registrar;

use App\Exceptions\NameComApiException;
use App\Models\Document;
use App\Models\Domain;
use App\Models\DomainLog;
use App\Models\User;
use App\Notifications\DomainAuthInfoRevealedNotification;
use App\Notifications\DomainTransferActivityNotification;
use Illuminate\Support\Facades\Notification;

/**
 * Transfer-out readiness for linked domains: lock state, lock/unlock, one-time auth code.
 * No money involved. The auth code is returned to the caller and NEVER stored, logged or audited.
 * DomainLog action names are deliberately neutral (no supplier name) because clients may see them.
 */
class NameComTransferService
{
    public const MAX_LOCK_CHANGES_PER_DAY = 5;   // clients only
    public const MAX_CODE_REQUESTS_PER_DAY = 3;  // clients only
    public const OWED_MESSAGE = 'Please clear outstanding invoices first.';

    public function __construct(private DomainRegistrarManager $registrar) {}

    /** @return array{locked: ?bool, transfer_lock_until: ?string, can_transfer: bool} */
    public function state(Domain $domain): array
    {
        $info = $this->registrar->namecomForDomain($domain)->getDomain($domain->name);
        return $this->stateFrom($info);
    }

    private function stateFrom(array $info): array
    {
        $locked = array_key_exists('locked', $info) ? (bool) $info['locked'] : null;
        $until = !empty($info['transferLockExpiresAt']) ? (string) $info['transferLockExpiresAt'] : null;
        return [
            'locked'              => $locked,
            'transfer_lock_until' => $until,
            'can_transfer'        => $locked === false,
        ];
    }

    /** Non-null message when a client must not unlock / get a code (owed invoices, expired or pending domain). */
    public function clientBlock(Domain $domain): ?string
    {
        if ($domain->status !== 'active') {
            return in_array($domain->status, ['expired'], true)
                ? 'This domain has expired. Please renew it and clear outstanding invoices first.'
                : 'This domain is not active yet, so it cannot be prepared for transfer.';
        }
        $owed = Document::withoutGlobalScopes()
            ->where('tenant_id', $domain->tenant_id)->where('client_id', $domain->client_id)
            ->where('type', 'invoice')
            ->whereIn('status', ['sent', 'overdue', 'partial', 'pending_approval'])
            ->whereNotNull('due_date')->where('due_date', '<', now()->toDateString())
            ->exists();
        return $owed ? self::OWED_MESSAGE : null;
    }

    private function used(Domain $domain, string $action): int
    {
        return DomainLog::where('domain_id', $domain->id)->where('action', $action)
            ->where('status', 'success')->where('created_at', '>=', now()->subDay())->count();
    }

    /** @return array{locked: ?bool, transfer_lock_until: ?string, can_transfer: bool} */
    public function setLock(Domain $domain, bool $lock, array $actor, bool $isClient): array
    {
        if ($isClient) {
            if (!$lock && ($m = $this->clientBlock($domain))) throw new \DomainException($m);
            if ($this->used($domain, 'transfer_lock_changed') >= self::MAX_LOCK_CHANGES_PER_DAY) {
                throw new \DomainException('Lock changes for this domain are limited to ' . self::MAX_LOCK_CHANGES_PER_DAY . ' per day. Try again tomorrow.');
            }
        }
        $driver = $this->registrar->namecomForDomain($domain);
        $info = $lock ? $driver->lockDomain($domain->name, $actor) : $driver->unlockDomain($domain->name, $actor);
        $state = $this->stateFrom($info);

        DomainLog::create([
            'tenant_id' => $domain->tenant_id, 'domain_id' => $domain->id, 'action' => 'transfer_lock_changed',
            'request'   => ['locked' => $lock] + $actor, 'status' => 'success',
        ]);
        $meta = $domain->meta ?? [];
        $meta['namecom'] = array_merge($meta['namecom'] ?? [], ['locked' => $state['locked'] ?? $lock]);
        $domain->update(['meta' => $meta]);

        if (!$lock) $this->notifyStaff($domain, 'unlocked', $isClient);
        return $state;
    }

    /** Returns the code ONCE; the caller must not keep it. */
    public function authCode(Domain $domain, array $actor, bool $isClient): string
    {
        if ($isClient) {
            if ($m = $this->clientBlock($domain)) throw new \DomainException($m);
            if ($this->used($domain, 'transfer_code_requested') >= self::MAX_CODE_REQUESTS_PER_DAY) {
                throw new \DomainException('Transfer code requests for this domain are limited to ' . self::MAX_CODE_REQUESTS_PER_DAY . ' per day. Try again tomorrow.');
            }
        }
        $code = $this->registrar->namecomForDomain($domain)->getAuthCode($domain->name, $actor);

        DomainLog::create([ // records THAT a code was requested, never the value
            'tenant_id' => $domain->tenant_id, 'domain_id' => $domain->id, 'action' => 'transfer_code_requested',
            'request'   => $actor, 'status' => 'success',
        ]);
        $this->notifyStaff($domain, 'code', $isClient);
        try {
            $client = $domain->client()->withoutGlobalScopes()->first();
            $tenant = \App\Models\Tenant::withoutGlobalScopes()->find($domain->tenant_id);
            if ($client && $tenant && ($client->email || $client->phone)) {
                $client->notify(new DomainAuthInfoRevealedNotification($domain, $tenant));
            }
        } catch (\Throwable $e) {
            \Log::warning('Transfer code notice failed', ['error' => $e->getMessage()]);
        }
        return $code;
    }

    private function notifyStaff(Domain $domain, string $event, bool $byClient): void
    {
        try {
            $staff = User::withPermission($domain->tenant_id, 'domains.transfer');
            if ($staff->isNotEmpty()) Notification::send($staff, new DomainTransferActivityNotification($domain, $event, $byClient));
        } catch (\Throwable $e) {
            report($e);
        }
    }
}
