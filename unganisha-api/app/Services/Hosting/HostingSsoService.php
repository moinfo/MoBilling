<?php

namespace App\Services\Hosting;

use App\Models\HostingAccount;
use App\Models\Server;
use App\Services\WhmService;

/**
 * Thin seam over WhmService::ssoUrl() (WHM create_user_session — needs a WHM
 * token with the "all" ACL) so callers that must never hit a real WHM in
 * tests (the WhatsApp bot) can bind a fake. Returns a short-lived one-time
 * cPanel login URL; callers must never log it.
 */
class HostingSsoService
{
    public function cpanelUrl(HostingAccount $account): string
    {
        $server = Server::withoutGlobalScopes()->find($account->server_id);
        if (!$server) {
            throw new \RuntimeException('Hosting server not found');
        }

        return (new WhmService($server))
            ->forAccount($account->id)
            ->ssoUrl($account->cpanel_username, 'cpaneld');
    }
}
