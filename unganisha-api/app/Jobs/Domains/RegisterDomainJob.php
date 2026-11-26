<?php

namespace App\Jobs\Domains;

use App\Models\Client;
use App\Models\Domain;
use App\Models\DomainLog;
use App\Notifications\DomainRegisteredNotification;
use App\Services\Registrar\FredHttpDriver;
use Illuminate\Support\Facades\Log;

class RegisterDomainJob extends BaseDomainJob
{
    public function __construct(public Domain $domain) {}

    public function handle(): void
    {
        $domain = $this->domain->fresh('client');

        // Idempotency guard: exact pending state only — a double-fire is a no-op.
        if (!$domain || $domain->status !== 'pending' || ($domain->meta['pending_action'] ?? null) !== 'register') {
            return;
        }

        $years = (int) ($domain->meta['pending_years'] ?? 1);

        $this->guard($domain, function () use ($domain, $years) {
            $driver = $this->driver($domain);
            $registrantContactId = $driver instanceof FredHttpDriver
                ? $this->registrantContactFor($driver, $domain->client)
                : null;

            $driver->register($domain->name, $years, [], $registrantContactId);

            $domain->update(['status' => 'active']);

            DomainLog::create([
                'tenant_id' => $domain->tenant_id,
                'domain_id' => $domain->id,
                'action'    => 'registered',
                'request'   => ['years' => $years, 'document_id' => $domain->meta['order_document_id'] ?? null],
                'status'    => 'success',
            ]);

            $this->clearPending($domain);
            $this->syncFromRegistry($domain);

            // Point the fresh domain at the tenant's hosting nameservers so it
            // resolves immediately. Best-effort — staff can change them later.
            if (!$domain->fresh()->nsset_handle) {
                $ns = \App\Models\Server::withoutGlobalScopes()
                    ->where('tenant_id', $domain->tenant_id)
                    ->where('is_active', true)
                    ->whereNotNull('nameservers')
                    ->value('nameservers')
                    ?: config('hosting.default_nameservers', []);
                $ns = is_string($ns) ? json_decode($ns, true) : $ns;
                if ($ns) {
                    try {
                        app(\App\Services\Registrar\NameserverService::class)
                            ->update($domain->fresh(), (array) $ns, ['auto' => 'post_register']);
                    } catch (\Throwable $e) {
                        Log::warning("Default NS attach failed for {$domain->name}: {$e->getMessage()}");
                    }
                }
            }

            if ($domain->client?->email || $domain->client?->phone) {
                try {
                    $domain->client->notify(new DomainRegisteredNotification($domain->fresh()));
                } catch (\Throwable $e) {
                    Log::warning("Domain registered email failed for {$domain->name}: {$e->getMessage()}");
                }
            }
        });
    }

    /**
     * Reuse the client's cached registry contact, or create one now from
     * their real name/email/phone and cache it on the Client row — so every
     * domain they register ends up with THEIR contact as registrant instead
     * of the platform's own CONTACT-MOINFOTECH (2026-11-26 .tz registry
     * compliance notice: 123+ domains all sharing one registrant). Best
     * effort: a client with no email, or any EPP hiccup, falls back to null
     * — the bridge then keeps its previous default rather than the
     * registration failing outright.
     */
    private function registrantContactFor(FredHttpDriver $driver, ?Client $client): ?string
    {
        if (!$client || !$client->email) {
            return null;
        }
        if ($client->registry_contact_id) {
            return $client->registry_contact_id;
        }

        try {
            $contactId = $driver->createContact([
                'name'        => $client->name,
                'email'       => $client->email,
                'city'        => $client->city,
                'street'      => array_values(array_filter([$client->address_1, $client->address_2])) ?: null,
                'org'         => $client->company_name,
                'postal_code' => $client->postcode,
                'phone'       => $client->phone,
            ]);
            $client->update(['registry_contact_id' => $contactId]);

            return $contactId;
        } catch (\Throwable $e) {
            Log::warning("Registrant contact creation failed for client {$client->id}: {$e->getMessage()}");

            return null;
        }
    }
}
