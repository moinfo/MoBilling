<?php

namespace App\Http\Controllers;

use App\Exceptions\WhmApiException;
use App\Jobs\Hosting\ChangeHostingPackage;
use App\Jobs\Hosting\ProvisionHostingAccount;
use App\Jobs\Hosting\ReactivateHostingAccount;
use App\Jobs\Hosting\SuspendHostingAccount;
use App\Jobs\Hosting\TerminateHostingAccount;
use App\Models\Client;
use App\Models\ClientSubscription;
use App\Models\HostingAccount;
use App\Models\ProductService;
use App\Models\Server;
use App\Services\WhmService;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class HostingAccountController extends Controller
{
    /**
     * Every cPanel account that actually exists on the WHM server(s), cross
     * referenced against hosting_accounts so staff can see what's already
     * tracked in MoBilling and what was created directly on the server (or
     * missed during a WHMCS import) and still needs linking to a client.
     */
    public function discover(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $servers = Server::where('tenant_id', $tenantId)->where('is_active', true)
            ->when($request->filled('server_id'), fn ($q) => $q->where('id', $request->server_id))
            ->get();

        $known = HostingAccount::withoutGlobalScopes()
            ->where('tenant_id', $tenantId)
            ->with('subscription.client:id,name')
            ->get()
            ->keyBy(fn ($a) => $a->server_id . '|' . strtolower($a->cpanel_username));

        $rows = [];
        $errors = [];

        foreach ($servers as $server) {
            try {
                $remote = (new WhmService($server))->listAccounts();
            } catch (WhmApiException $e) {
                $errors[] = "{$server->name}: {$e->getMessage()}";
                continue;
            }

            foreach ($remote as $acct) {
                $username = (string) ($acct['user'] ?? '');
                if ($username === '') {
                    continue;
                }
                $local = $known->get($server->id . '|' . strtolower($username));

                $rows[] = [
                    'server_id'          => $server->id,
                    'server_name'        => $server->name,
                    'cpanel_username'    => $username,
                    'domain'             => $acct['domain'] ?? null,
                    'email'              => $acct['email'] ?? null,
                    'plan'               => $acct['plan'] ?? null,
                    'disk_used'          => $acct['diskused'] ?? null,
                    'disk_limit'         => $acct['disklimit'] ?? null,
                    'suspended'          => (bool) ($acct['suspended'] ?? false),
                    'hosting_account_id' => $local?->id,
                    'client'             => $local?->subscription?->client
                        ? ['id' => $local->subscription->client->id, 'name' => $local->subscription->client->name]
                        : null,
                    'imported'           => (bool) $local,
                ];
            }
        }

        // Search across the merged list (username/domain/client name) —
        // simplest done after merging since it spans two data sources.
        if ($request->filled('search')) {
            $s = strtolower($request->search);
            $rows = array_values(array_filter($rows, fn ($r) =>
                str_contains(strtolower($r['cpanel_username']), $s)
                || str_contains(strtolower((string) $r['domain']), $s)
                || str_contains(strtolower((string) ($r['client']['name'] ?? '')), $s)));
        }
        if ($request->filled('imported')) {
            $want = $request->boolean('imported');
            $rows = array_values(array_filter($rows, fn ($r) => $r['imported'] === $want));
        }

        return response()->json(['data' => $rows, 'errors' => $errors]);
    }

    /**
     * Link a discovered-but-untracked cPanel account to a client: creates the
     * subscription it never had in MoBilling, then the hosting_accounts row
     * pointing at it. No WHM call — the account already exists on the server.
     */
    public function import(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'server_id'          => ['required', 'uuid', Rule::exists('servers', 'id')->where('tenant_id', $tenantId)],
            'cpanel_username'    => 'required|string|max:64',
            'domain'             => 'required|string|max:255',
            'client_id'          => ['required', 'uuid', Rule::exists('clients', 'id')->where('tenant_id', $tenantId)],
            'product_service_id' => ['required', 'uuid', Rule::exists('product_services', 'id')->where('tenant_id', $tenantId)],
        ]);

        $exists = HostingAccount::withoutGlobalScopes()
            ->where('server_id', $data['server_id'])
            ->where('cpanel_username', $data['cpanel_username'])
            ->exists();
        if ($exists) {
            return response()->json(['message' => 'This cPanel account is already imported.'], 422);
        }

        $client = Client::withoutGlobalScopes()->findOrFail($data['client_id']);
        $product = ProductService::withoutGlobalScopes()->findOrFail($data['product_service_id']);

        // Live status/package straight from the server, so the imported
        // record isn't just guessed from the discover-list snapshot.
        $server = Server::findOrFail($data['server_id']);
        $summary = [];
        try {
            $summary = (new WhmService($server))->accountSummary($data['cpanel_username']);
        } catch (WhmApiException) {
            // best-effort — fall back to the product's package/active status
        }

        $subscription = ClientSubscription::create([
            'tenant_id'          => $tenantId,
            'client_id'          => $client->id,
            'product_service_id' => $product->id,
            'label'              => $data['domain'],
            'quantity'           => 1,
            'start_date'         => now(),
            'status'             => ($summary['suspended'] ?? false) ? 'suspended' : 'active',
            'metadata'           => ['imported_existing' => true],
        ]);

        $hostingAccount = HostingAccount::create([
            'tenant_id'              => $tenantId,
            'client_subscription_id' => $subscription->id,
            'server_id'              => $data['server_id'],
            'domain'                 => $data['domain'],
            'cpanel_username'        => $data['cpanel_username'],
            'package'                => $summary['plan'] ?? $product->cpanel_package,
            'status'                 => ($summary['suspended'] ?? false) ? 'suspended' : 'active',
            'last_synced_at'         => now(),
            'meta'                   => ['adopted_existing' => true],
        ]);

        return response()->json([
            'data'    => $hostingAccount,
            'message' => "{$data['domain']} imported and linked to {$client->name}.",
        ], 201);
    }

    public function index(Request $request)
    {
        $query = HostingAccount::with(['server:id,name,hostname', 'subscription.client:id,name'])
            ->orderByDesc('created_at');

        if ($request->filled('status')) $query->where('status', $request->status);
        if ($request->filled('server_id')) $query->where('server_id', $request->server_id);
        if ($request->filled('search')) {
            $s = $request->search;
            $query->where(fn ($q) => $q
                ->where('domain', 'like', "%{$s}%")
                ->orWhere('cpanel_username', 'like', "%{$s}%"));
        }

        return response()->json(['data' => $query->paginate($request->get('per_page', 20))]);
    }

    /** Manually provision the hosting account for a subscription. */
    public function provision(ClientSubscription $clientSubscription)
    {
        if ($clientSubscription->hostingAccount()->exists()) {
            return response()->json(['message' => 'Subscription already has a hosting account.'], 422);
        }
        if ($clientSubscription->productService?->provisioning_type !== 'whm_cpanel') {
            return response()->json(['message' => 'This product is not configured for WHM provisioning.'], 422);
        }

        ProvisionHostingAccount::dispatch($clientSubscription);

        return response()->json(['message' => 'Provisioning started.'], 202);
    }

    public function suspend(HostingAccount $hostingAccount)
    {
        SuspendHostingAccount::dispatch($hostingAccount, 'Suspended by admin');
        $this->notifyStatusChange($hostingAccount, suspended: true);
        return response()->json(['message' => 'Suspension started.'], 202);
    }

    public function unsuspend(HostingAccount $hostingAccount)
    {
        ReactivateHostingAccount::dispatch($hostingAccount);
        $this->notifyStatusChange($hostingAccount, suspended: false);
        return response()->json(['message' => 'Unsuspension started.'], 202);
    }

    /** Tell the client about a manual suspend/restore (auto flows notify elsewhere). */
    private function notifyStatusChange(HostingAccount $hostingAccount, bool $suspended): void
    {
        try {
            $client = $hostingAccount->subscription?->client;
            $tenant = \App\Models\Tenant::withoutGlobalScopes()->find($hostingAccount->tenant_id);
            if ($client && $tenant && ($client->email || $client->phone)) {
                $client->notify(new \App\Notifications\HostingStatusChangedNotification($hostingAccount, $tenant, $suspended));
            }
        } catch (\Throwable $e) {
            \Illuminate\Support\Facades\Log::warning('Hosting status notice failed', ['error' => $e->getMessage()]);
        }
    }

    public function terminate(HostingAccount $hostingAccount)
    {
        TerminateHostingAccount::dispatch($hostingAccount);
        return response()->json(['message' => 'Termination started.'], 202);
    }

    public function changePackage(Request $request, HostingAccount $hostingAccount)
    {
        $data = $request->validate(['package' => 'required|string|max:255']);
        ChangeHostingPackage::dispatch($hostingAccount, $data['package']);
        return response()->json(['message' => 'Package change started.'], 202);
    }

    /** One-time cPanel SSO URL. */
    public function sso(HostingAccount $hostingAccount)
    {
        try {
            $url = (new WhmService($hostingAccount->server))
                ->forAccount($hostingAccount->id)
                ->ssoUrl($hostingAccount->cpanel_username);

            return response()->json(['url' => $url]);
        } catch (WhmApiException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }
    }

    public function logs(HostingAccount $hostingAccount)
    {
        return response()->json(['data' => $hostingAccount->logs()->limit(50)->get()]);
    }
}
