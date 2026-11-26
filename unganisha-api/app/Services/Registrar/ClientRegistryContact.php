<?php

namespace App\Services\Registrar;

use App\Helpers\PhoneHelper;
use App\Models\Client;
use App\Models\Domain;
use Illuminate\Support\Facades\Log;

/**
 * Resolves (or creates) the FRED/.tz registry contact a Client should be
 * the registrant of — shared by RegisterDomainJob (new registrations) and
 * FixSharedRegistrantContacts (backfilling the 123+ domains that shared
 * CONTACT-MOINFOTECH before this existed, 2026-11-26 .tz compliance notice).
 * fredVoice() and selfManagedHandle() are also used directly by
 * PortalDomainController/DomainController's WHOIS-contact edit screens.
 */
class ClientRegistryContact
{
    /**
     * Reuse the client's cached registry contact, or create one now from
     * their real name/email/phone and cache it on the Client row. Best
     * effort: a client with no email, or any EPP hiccup, returns null —
     * callers fall back to their own previous default rather than failing.
     */
    public static function resolve(FredHttpDriver $driver, ?Client $client): ?string
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
                'phone'       => self::fredVoice($client->phone),
            ]);
            $client->update(['registry_contact_id' => $contactId]);

            return $contactId;
        } catch (\Throwable $e) {
            Log::warning("Registrant contact creation failed for client {$client->id}: {$e->getMessage()}");

            return null;
        }
    }

    /**
     * FRED's EPP contact schema wants voice/fax as "+<country-code>.<number>"
     * (e164StringType: `(\+[0-9]{1,3}\.[0-9]{1,14})?`) — a dot, not the plain
     * E.164 MoBilling stores phones as everywhere else. Defaults to Tanzania
     * when the number carries no explicit country code, same assumption the
     * contact's country_code already makes elsewhere in this flow.
     */
    public static function fredVoice(?string $phone): ?string
    {
        if (!$phone) {
            return null;
        }
        $national = PhoneHelper::normalize($phone);
        if (!$national) {
            return null;
        }
        $cc = PhoneHelper::countryCode($phone) ?? '255';

        return "+{$cc}.{$national}";
    }

    /**
     * The contact id to edit for this domain's WHOIS, or null when it isn't
     * safe to: only a contact THIS platform created for THIS exact client
     * (resolve(), above) is one we hold the full, correct field set for. A
     * pre-existing/imported handle (e.g. a WHMCS-era CONTACT-W163) might
     * carry fields we never set and have no record of — editing it here
     * could silently blank them out, so it stays contact-support-only.
     */
    public static function selfManagedHandle(Domain $domain): ?string
    {
        $client = $domain->client ?? $domain->client()->withoutGlobalScopes()->first();
        if (!$client?->registry_contact_id || $client->registry_contact_id !== $domain->registrant_handle) {
            return null;
        }

        return $client->registry_contact_id;
    }
}
