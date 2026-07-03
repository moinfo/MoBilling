<?php

namespace App\Http\Controllers;

use App\Exceptions\WhmApiException;
use App\Jobs\Hosting\ChangeHostingPackage;
use App\Jobs\Hosting\ProvisionHostingAccount;
use App\Jobs\Hosting\ReactivateHostingAccount;
use App\Jobs\Hosting\SuspendHostingAccount;
use App\Jobs\Hosting\TerminateHostingAccount;
use App\Models\ClientSubscription;
use App\Models\HostingAccount;
use App\Services\WhmService;
use Illuminate\Http\Request;

class HostingAccountController extends Controller
{
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
        return response()->json(['message' => 'Suspension started.'], 202);
    }

    public function unsuspend(HostingAccount $hostingAccount)
    {
        ReactivateHostingAccount::dispatch($hostingAccount);
        return response()->json(['message' => 'Unsuspension started.'], 202);
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
