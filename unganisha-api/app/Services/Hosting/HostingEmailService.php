<?php

namespace App\Services\Hosting;

use App\Models\HostingAccount;
use App\Models\Server;
use App\Services\WhmService;

/**
 * Thin seam over WhmService for the WhatsApp bot's mailbox creation so tests can
 * bind a fake and never hit a real WHM. The password passed to create() must never
 * be logged or messaged anywhere.
 */
class HostingEmailService
{
    private function whm(HostingAccount $account): WhmService
    {
        $server = Server::withoutGlobalScopes()->find($account->server_id);
        if (!$server) {
            throw new \RuntimeException('Hosting server not found');
        }
        return (new WhmService($server))->forAccount($account->id);
    }

    /** @return array{count:int, limit:?int} limit null = unlimited/unknown (WHM's maxpop) */
    public function usage(HostingAccount $account): array
    {
        $whm = $this->whm($account);
        $count = count($whm->emailAccounts($account->cpanel_username));
        $max = $whm->accountSummary($account->cpanel_username)['maxpop'] ?? null;
        $limit = is_numeric($max) && (int) $max > 0 ? (int) $max : null;

        return ['count' => $count, 'limit' => $limit];
    }

    /** Unlimited quota is not granted: default 1 GB mailbox. */
    public function create(HostingAccount $account, string $localPart, string $password, int $quotaMb = 1024): void
    {
        $this->whm($account)->addEmailAccount($account->cpanel_username, $localPart, $account->domain, $password, $quotaMb);
    }
}
