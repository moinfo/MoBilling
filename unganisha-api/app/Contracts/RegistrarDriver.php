<?php

namespace App\Contracts;

/**
 * Driver contract for domain registrars (docs/DOMAIN_REGISTRAR_INTEGRATION.md §6).
 * First implementation: FredHttpDriver (.tz via the fred-client Django service).
 *
 * NOTE: register/renew/transferIn SPEND REAL REGISTRY CREDIT — only call them
 * from payment-gated jobs, never from tests or read paths.
 */
interface RegistrarDriver
{
    /** @return array{available: bool, reason: ?string} */
    public function check(string $domain): array;

    /** @return array raw domain info (status, expiry, handles) from the registry */
    public function info(string $domain): array;

    /** @return array{zone: string, credit: string}[] registrar prepaid balances */
    public function credit(): array;

    /** @return array registry response */
    public function register(string $domain, int $years = 1, array $nameservers = []): array;

    public function renew(string $domain, int $years = 1): array;

    public function transferIn(string $domain, string $authInfo): array;

    public function updateDomain(string $domain, array $changes): array;
}
