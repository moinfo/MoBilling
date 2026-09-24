<?php

namespace App\Services\Registrar;

use App\Exceptions\NameComApiException;
use App\Exceptions\RegistrarApiException;
use App\Models\Client;
use App\Models\Document;
use App\Models\Domain;
use App\Models\DomainLog;
use App\Models\DomainTld;
use App\Models\NameComAccount;
use App\Models\NameComAuditLog;
use App\Models\NameComSettings;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Notification;

/**
 * Registration at Name.com SPENDS REAL MONEY. This is the ONLY code path that may call
 * NameComDriver::createDomain (the driver demands this class), used by both the staff
 * "Register at Name.com" action (mode=manual, explicit confirmation of the USD cost)
 * and the optional auto mode (mode=auto, tenant setting, off by default, with safeguards).
 */
class NameComRegistrationService
{
    public function __construct(private DomainRegistrarManager $registrar) {}

    public static function isNameComOrder(Domain $d): bool
    {
        return ($d->meta['registrar'] ?? null) === 'namecom';
    }

    public static function isQueued(Domain $d): bool
    {
        return self::isNameComOrder($d) && $d->status === 'pending' && !empty($d->meta['awaiting_manual_registration']);
    }

    private const COUNTRIES = ['tanzania' => 'TZ', 'united republic of tanzania' => 'TZ', 'kenya' => 'KE', 'uganda' => 'UG', 'rwanda' => 'RW', 'burundi' => 'BI',
        'south africa' => 'ZA', 'nigeria' => 'NG', 'united states' => 'US', 'usa' => 'US', 'united kingdom' => 'GB', 'uk' => 'GB'];

    /**
     * Map a Client to the Name.com contact shape. Nothing is invented: missing required fields are reported.
     * (Fallbacks: first/last name from "name" when both are blank; address_1 <- address; state <- city.)
     * @return array{0: array, 1: string[]} [contact, missing labels]
     */
    public static function buildContact(Client $c): array
    {
        $first = trim((string) $c->first_name);
        $last = trim((string) $c->last_name);
        if ($first === '' && $last === '' && trim((string) $c->name) !== '' && str_contains(trim((string) $c->name), ' ')) {
            $parts = preg_split('/\s+/', trim((string) $c->name));
            $last = array_pop($parts);
            $first = implode(' ', $parts);
        }
        $address1 = trim((string) ($c->address_1 ?: $c->address));
        $city = trim((string) $c->city);
        $state = trim((string) ($c->state ?: $c->city));
        $zip = trim((string) $c->postcode);

        $country = trim((string) $c->country);
        if (!preg_match('/^[A-Za-z]{2}$/', $country)) $country = self::COUNTRIES[strtolower($country)] ?? '';
        $country = strtoupper($country);

        $phone = preg_replace('/[\s\-().]/', '', (string) $c->phone);
        if ($phone !== '' && $phone[0] !== '+') {
            if (str_starts_with($phone, '00')) $phone = '+' . substr($phone, 2);
            elseif ($country === 'TZ' && str_starts_with($phone, '0')) $phone = '+255' . substr($phone, 1);
            elseif ($country === 'TZ' && str_starts_with($phone, '255')) $phone = '+' . $phone;
            else $phone = '';
        }
        if (!preg_match('/^\+[1-9]\d{7,14}$/', $phone)) $phone = '';

        $email = trim((string) $c->email);
        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) $email = '';

        $contact = ['firstName' => $first, 'lastName' => $last, 'address1' => $address1, 'city' => $city, 'state' => $state, 'zip' => $zip,
            'country' => $country, 'email' => $email, 'phone' => $phone];
        $labels = ['firstName' => 'first name', 'lastName' => 'last name', 'address1' => 'address', 'city' => 'city', 'state' => 'state/region',
            'zip' => 'postal code', 'country' => 'country (ISO 2-letter, e.g. TZ)', 'email' => 'valid email', 'phone' => 'phone in international format (e.g. +255...)'];
        $missing = [];
        foreach ($labels as $k => $l) if ($contact[$k] === '') $missing[] = $l;

        if (trim((string) $c->address_2) !== '') $contact['address2'] = trim((string) $c->address_2);
        if (trim((string) $c->company_name) !== '') $contact['companyName'] = trim((string) $c->company_name);

        return [$contact, $missing];
    }

    public static function contactsPayload(array $contact): array
    {
        return ['registrant' => $contact, 'admin' => $contact, 'tech' => $contact, 'billing' => $contact];
    }

    private function years(Domain $d): int
    {
        return max(1, min(10, (int) ($d->meta['namecom_years'] ?? 1)));
    }

    /**
     * Everything staff must see before confirming. Two READ calls at Name.com (availability + live price).
     */
    public function preview(Domain $d, ?string $accountId = null): array
    {
        $blockers = [];
        $notes = [];
        $years = $this->years($d);
        $tld = strtolower(explode('.', $d->name, 2)[1] ?? '');

        if (!self::isQueued($d)) $blockers[] = 'This domain is not waiting for registration at Name.com.';

        $client = Client::withoutGlobalScopes()->where('tenant_id', $d->tenant_id)->find($d->client_id);
        [$contact, $missing] = $client ? self::buildContact($client) : [[], ['client record']];
        if ($missing) $blockers[] = 'The client record is missing: ' . implode(', ', $missing) . '. Update the client, then try again.';

        $row = DomainTld::where('tenant_id', $d->tenant_id)->where('tld', $tld)->where('registrar', 'namecom')->first();
        $expected = $row && $row->usd_register !== null ? round($row->usd_register * $years, 2) : null;

        $account = $accountId ? NameComAccount::findFor($d->tenant_id, $accountId) : NameComAccount::defaultFor($d->tenant_id);
        if ($accountId && !$account) $blockers[] = 'The selected Name.com account no longer exists.';
        $available = null; $reason = null; $live = null; $usd = null; $priceChanged = false;
        if (self::isQueued($d) && $account) {
            try {
                $driver = $this->registrar->namecomFor($d->tenant_id, $account->id);
                $a = $driver->checkAvailability($d->name);
                $available = $a['available']; $reason = $a['reason'];
                if (!$available && !empty($d->meta['namecom_uncertain'])) {
                    $notes[] = 'A previous attempt may already have gone through at Name.com. Confirming will check the Name.com account first (no new purchase if it is already there).';
                    $available = null;
                } elseif (!$available) {
                    $blockers[] = 'Not available at Name.com right now' . ($reason ? " ({$reason})" : '') . '.';
                }
                $p = $driver->tldPriceFor($tld, $years);
                $live = $p ? ($p['registrationPrice'] ?? null) : null;
                if ($live === null) {
                    $blockers[] = "Name.com returned no registration price for .{$tld}.";
                } else {
                    $live = (float) $live;
                    $usd = $live; // Name.com prices the requested duration (total for $years)
                    if ($expected !== null && $usd > $expected * 1.01 + 0.005) $priceChanged = true;
                }
            } catch (NameComApiException | RegistrarApiException $e) {
                $blockers[] = preg_replace('/^Registrar \S+ failed: /', '', $e->getMessage());
            }
        }

        $doc = ($d->meta['order_document_id'] ?? null) ? Document::withoutGlobalScopes()->find($d->meta['order_document_id']) : null;

        return [
            'domain'        => $d->name,
            'client'        => $client ? ['id' => $client->id, 'name' => $client->name] : null,
            'years'         => $years,
            'contact'       => $contact,
            'missing'       => $missing,
            'account'       => $account ? ['id' => $account->id, 'label' => $account->displayLabel(), 'username' => $account->username, 'is_sandbox' => (bool) $account->is_sandbox] : null,
            'accounts'      => NameComAccount::withoutGlobalScopes()->where('tenant_id', $d->tenant_id)->orderByDesc('is_default')->orderBy('created_at')->get()
                ->map(fn ($a) => ['id' => $a->id, 'label' => $a->displayLabel(), 'username' => $a->username, 'is_default' => (bool) $a->is_default, 'status' => $a->status])->all(),
            'usd_cost'      => $usd,
            'usd_expected'  => $expected,
            'price_changed' => $priceChanged,
            'available'     => $available,
            'invoice_total' => $doc ? (float) $doc->total : null,
            'invoice_number' => $doc?->document_number,
            'request'       => ['domain' => ['domainName' => $d->name, 'contacts' => '(registrant/admin/tech/billing = client contact above)'], 'years' => $years, 'purchaseType' => 'registration'],
            'blockers'      => $blockers,
            'notes'         => $notes,
            'can_register'  => empty($blockers),
            'uncertain'     => !empty($d->meta['namecom_uncertain']),
        ];
    }

    /**
     * Perform the registration (single create call). Throws \DomainException with a clear message when refused.
     * @param float|null $confirmedUsd the USD cost the staff member saw and confirmed (required for manual mode)
     */
    public function register(Domain $domain, array $actor, string $mode = 'manual', ?float $confirmedUsd = null, ?string $accountId = null): Domain
    {
        // claim the row so a double click / parallel job cannot buy twice
        $claimed = DB::transaction(function () use ($domain) {
            $d = Domain::withoutGlobalScopes()->lockForUpdate()->find($domain->id);
            if (!$d || !self::isQueued($d)) throw new \DomainException('This domain is not waiting for registration at Name.com.');
            $started = $d->meta['namecom_registering'] ?? null;
            if ($started && Carbon::parse($started)->gt(now()->subMinutes(5))) throw new \DomainException('A registration for this domain is already in progress.');
            $d->update(['meta' => array_merge($d->meta, ['namecom_registering' => now()->toIso8601String()])]);
            return $d->fresh();
        });

        try {
            return $this->doRegister($claimed, $actor, $mode, $confirmedUsd, $accountId);
        } finally {
            $f = Domain::withoutGlobalScopes()->find($domain->id);
            if ($f && isset($f->meta['namecom_registering'])) {
                $m = $f->meta; unset($m['namecom_registering']);
                $f->update(['meta' => $m]);
            }
        }
    }

    private function doRegister(Domain $d, array $actor, string $mode, ?float $confirmedUsd, ?string $accountId = null): Domain
    {
        $account = $accountId ? NameComAccount::findFor($d->tenant_id, $accountId) : NameComAccount::defaultFor($d->tenant_id);
        if (!$account) throw new \DomainException('The selected Name.com account does not exist.');
        $actor = $actor + ['account_id' => $account->id, 'account' => $account->displayLabel()];
        $driver = $this->registrar->namecomFor($d->tenant_id, $account->id);

        // A previous attempt with an unknown outcome: adopt it if it did go through (no spend).
        if (!empty($d->meta['namecom_uncertain'])) {
            try {
                // check the account where the unknown attempt was made (may differ from the one chosen now)
                $prevId = $d->meta['namecom_attempt_account'] ?? $account->id;
                $prev = NameComAccount::findFor($d->tenant_id, $prevId) ?? $account;
                $info = $this->registrar->namecomFor($d->tenant_id, $prev->id)->getDomain($d->name);
                return $this->finalize($d, $info, ['adopted' => true, 'account_id' => $prev->id, 'account' => $prev->displayLabel()] + $actor, $mode);
            } catch (NameComApiException $e) {
                if ($e->httpStatus !== 404) throw new \DomainException($e->getMessage());
                $m = $d->meta; unset($m['namecom_uncertain'], $m['namecom_attempt_account']); $d->update(['meta' => $m]); $d = $d->fresh();
            }
        }

        $p = $this->preview($d, $account->id);
        if ($p['blockers']) throw new \DomainException(implode(' ', $p['blockers']));
        if ($mode === 'manual') {
            if ($confirmedUsd === null || abs($confirmedUsd - (float) $p['usd_cost']) > 0.005) {
                throw new \DomainException('The USD cost changed (now $' . number_format((float) $p['usd_cost'], 2) . '). Review and confirm again.');
            }
        }
        if ($p['price_changed'] && $mode === 'auto') throw new \DomainException('The Name.com price is higher than the synced price.');

        try {
            $res = $driver->createDomain($this, $d->name, $p['years'], self::contactsPayload($p['contact']), [
                'mode' => $mode, 'domain_id' => $d->id, 'usd_cost' => $p['usd_cost'], 'client_id' => $d->client_id,
            ] + $actor);
        } catch (NameComApiException $e) {
            if ($e->httpStatus === 0) { // timeout / network: outcome unknown, never blind-retry
                $d->update(['meta' => array_merge($d->fresh()->meta, ['namecom_uncertain' => true, 'namecom_attempt_account' => $account->id])]);
            }
            DomainLog::create(['tenant_id' => $d->tenant_id, 'domain_id' => $d->id, 'action' => 'namecom_register_failed',
                'request' => ['mode' => $mode, 'years' => $p['years']] + $actor, 'status' => 'failed', 'error' => mb_substr($e->getMessage(), 0, 250)]);
            throw new \DomainException($e->getMessage());
        }

        return $this->finalize($d->fresh(), $res['domain'] ?? [], ['order' => $res['order'] ?? null, 'total_paid_usd' => $res['totalPaid'] ?? null, 'years' => $p['years']] + $actor, $mode);
    }

    private function finalize(Domain $d, array $info, array $log, string $mode): Domain
    {
        $expires = substr((string) ($info['expireDate'] ?? ''), 0, 10) ?: now()->addYears($this->years($d))->toDateString();
        $created = substr((string) ($info['createDate'] ?? ''), 0, 10) ?: now()->toDateString();
        $ns = NameComDriver::extractNameservers($info);

        $meta = $d->fresh()->meta ?? [];
        unset($meta['awaiting_manual_registration'], $meta['pending_action'], $meta['pending_years'], $meta['namecom_uncertain'], $meta['namecom_registering'], $meta['namecom_attempt_account']);
        $meta['unmanaged'] = true;
        $meta['namecom'] = [
            'nameservers' => $ns, 'locked' => $info['locked'] ?? null, 'autorenew' => $info['autorenewEnabled'] ?? null,
            'original_nameservers' => $ns, 'synced_at' => now()->toIso8601String(),
            'order' => $log['order'] ?? null, 'paid_usd' => $log['total_paid_usd'] ?? null,
            'account_id' => $log['account_id'] ?? null,
        ];
        $d->update(['status' => 'active', 'registered_at' => $created, 'expires_at' => $expires, 'auto_renew' => false, 'meta' => $meta]);

        DomainLog::create(['tenant_id' => $d->tenant_id, 'domain_id' => $d->id, 'action' => 'namecom_registered',
            'request' => ['mode' => $mode] + $log, 'status' => 'success']);

        try { // customer-facing: neutral "your domain is ready" (mail + push only)
            $client = Client::withoutGlobalScopes()->find($d->client_id);
            if ($client && ($client->email || $client->phone)) $client->notify(new \App\Notifications\DomainReadyNotification($d->fresh()));
        } catch (\Throwable $e) {
            Log::warning("Domain ready notice failed for {$d->name}: {$e->getMessage()}");
        }

        return $d->fresh();
    }

    // ── paid-invoice hook ──

    /** Called from DocumentObserver once a Name.com domain order is paid. Never throws. */
    public static function onOrderPaid(Domain $d): void
    {
        try {
            $staff = User::withPermission($d->tenant_id, 'domains.create');
            if ($staff->isNotEmpty()) {
                Notification::send($staff, new \App\Notifications\NameComRegistrationPendingNotification($d));
            }
        } catch (\Throwable $e) {
            report($e);
        }

        try {
            if (NameComSettings::forTenant($d->tenant_id)->auto_register) {
                \App\Jobs\Domains\AutoRegisterNameComDomainJob::dispatch($d);
            }
        } catch (\Throwable $e) {
            report($e);
        }
    }

    /**
     * Auto mode. Same code path as manual, gated by: setting ON, USD cost <= cap, <= N auto registrations
     * today, availability/price re-check. Anything else leaves the domain in the manual queue.
     * @return array{registered: bool, reason: ?string}
     */
    public function autoRegister(Domain $d): array
    {
        $s = NameComSettings::forTenant($d->tenant_id);
        if (!$s->auto_register) return ['registered' => false, 'reason' => 'Auto-register is off.'];

        try {
            if (!self::isQueued($d)) return ['registered' => false, 'reason' => 'Not in the registration queue.'];

            $today = NameComAuditLog::withoutGlobalScopes()->where('tenant_id', $d->tenant_id)->where('action', 'domain.register')
                ->whereNull('error')->where('request->mode', 'auto')->where('created_at', '>=', now()->startOfDay())->count();
            if ($today >= $s->auto_daily_limit) throw new \DomainException("Daily auto-registration limit ({$s->auto_daily_limit}) reached.");

            $p = $this->preview($d);
            if ($p['blockers']) throw new \DomainException(implode(' ', $p['blockers']));
            if ($p['usd_cost'] === null || $p['usd_cost'] > $s->auto_cap_usd) {
                throw new \DomainException('USD cost $' . number_format((float) $p['usd_cost'], 2) . ' is above the per-domain cap of $' . number_format($s->auto_cap_usd, 2) . '.');
            }
            if ($p['price_changed']) throw new \DomainException('Price is higher than the synced price.');

            $this->register($d, ['auto' => true], 'auto', (float) $p['usd_cost']);
            return ['registered' => true, 'reason' => null];
        } catch (\Throwable $e) {
            $reason = $e->getMessage();
            Log::warning("Name.com auto-registration left in manual queue: {$d->name}: {$reason}");
            try {
                $staff = User::withPermission($d->tenant_id, 'domains.create');
                if ($staff->isNotEmpty()) Notification::send($staff, new \App\Notifications\NameComRegistrationPendingNotification($d, $reason));
            } catch (\Throwable $n) {
                report($n);
            }
            return ['registered' => false, 'reason' => $reason];
        }
    }
}
