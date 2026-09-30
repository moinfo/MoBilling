<?php

namespace App\Http\Controllers\Portal;

use App\Http\Controllers\Controller;
use App\Models\Client;
use App\Models\ResellerApplication;
use App\Models\Tenant;
use App\Models\User;
use App\Notifications\ResellerApplicationSubmittedNotification;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Notification;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * "Apply for white-label reseller" — a bigger upgrade than the existing
 * narrow domain-reseller feature (Client::isReseller()/PortalResellerController):
 * this is a request for a whole separate Tenant of the applicant's own. One
 * pending application per client at a time; staff review it under
 * Admin\ResellerApplicationController.
 */
class PortalResellerApplicationController extends Controller
{
    private function client(Request $request): Client
    {
        return Client::withoutGlobalScopes()->findOrFail($request->user()->client_id);
    }

    /** The client's own application (any status), or null if they've never applied. */
    public function show(Request $request)
    {
        $client = $this->client($request);

        $application = ResellerApplication::withoutGlobalScopes()
            ->where('tenant_id', $request->user()->tenant_id)
            ->where('client_id', $client->id)
            ->latest('created_at')
            ->first();

        return response()->json(['data' => $application]);
    }

    private function primaryAppHosts(): array
    {
        $frontend = config('app.frontend_url', 'https://mobilling.co.tz');
        $host = strtolower((string) parse_url($frontend, PHP_URL_HOST));
        return array_filter([$host]);
    }

    private function isOwnDomainOrSubdomain(string $domain): bool
    {
        foreach ($this->primaryAppHosts() as $host) {
            if ($domain === $host || Str::endsWith($domain, '.' . $host)) {
                return true;
            }
        }
        return false;
    }

    public function store(Request $request)
    {
        $user = $request->user();
        $tenantId = $user->tenant_id;
        $client = $this->client($request);

        // Existing narrower reseller feature already uses the word "reseller"
        // for a different thing — this endpoint is deliberately for the
        // bigger white-label-tenant upgrade, gated to the portal admin the
        // same way other significant portal actions in this app are.
        if (!$user->isPortalAdmin()) {
            abort(403, 'Only the portal account admin can submit a reseller application.');
        }

        $data = $request->validate([
            'requested_domain' => ['required', 'string', 'max:255', 'regex:/^(?!-)[a-z0-9-]{1,63}(?<!-)(\.(?!-)[a-z0-9-]{1,63}(?<!-))+$/i'],
            'brand_name'       => ['required', 'string', 'max:255'],
            'categories'       => ['required', 'array', 'min:1'],
            'categories.*'     => [Rule::in(ResellerApplication::CATEGORIES)],
            'contact_name'     => ['required', 'string', 'max:255'],
            'contact_email'    => ['required', 'email', 'max:255'],
            'contact_phone'    => ['nullable', 'string', 'max:30'],
        ]);

        $domain = strtolower(trim($data['requested_domain']));

        $lock = Cache::lock("reseller-application:{$client->id}", 10);
        try {
            return $lock->block(5, function () use ($domain, $data, $client, $tenantId) {
                $existingPending = ResellerApplication::withoutGlobalScopes()
                    ->where('tenant_id', $tenantId)->where('client_id', $client->id)
                    ->where('status', 'pending')->exists();
                if ($existingPending) {
                    return response()->json(['message' => 'You already have a reseller application pending review.'], 409);
                }

                $existingApproved = ResellerApplication::withoutGlobalScopes()
                    ->where('tenant_id', $tenantId)->where('client_id', $client->id)
                    ->whereIn('status', ['approved', 'provisioned'])->exists();
                if ($existingApproved) {
                    return response()->json(['message' => 'You already have an approved reseller application.'], 409);
                }

                if ($this->isOwnDomainOrSubdomain($domain)) {
                    throw ValidationException::withMessages(['requested_domain' => ['This domain is not available.']]);
                }

                if (Tenant::withoutGlobalScopes()->whereRaw('LOWER(custom_domain) = ?', [$domain])->exists()) {
                    throw ValidationException::withMessages(['requested_domain' => ['This domain is already in use.']]);
                }

                $domainTaken = ResellerApplication::withoutGlobalScopes()
                    ->whereRaw('LOWER(requested_domain) = ?', [$domain])
                    ->whereIn('status', ['pending', 'approved', 'provisioned'])
                    ->exists();
                if ($domainTaken) {
                    throw ValidationException::withMessages(['requested_domain' => ['This domain is already requested by another application.']]);
                }

                $application = ResellerApplication::withoutGlobalScopes()->create([
                    'tenant_id'        => $tenantId,
                    'client_id'        => $client->id,
                    'requested_domain' => $domain,
                    'brand_name'       => $data['brand_name'],
                    'categories'       => array_values(array_unique($data['categories'])),
                    'contact_name'     => $data['contact_name'],
                    'contact_email'    => $data['contact_email'],
                    'contact_phone'    => $data['contact_phone'] ?? null,
                    'status'           => 'pending',
                ]);

                try {
                    $staff = User::withPermission($tenantId, 'reseller_applications.manage');
                    if ($staff->isNotEmpty()) {
                        Notification::send($staff, new ResellerApplicationSubmittedNotification($application));
                    }
                } catch (\Throwable $e) {
                    report($e);
                }

                return response()->json([
                    'data'    => $application,
                    'message' => 'Your reseller application has been submitted for review.',
                ], 201);
            });
        } catch (\Illuminate\Contracts\Cache\LockTimeoutException) {
            return response()->json(['message' => 'Still processing your previous request — please wait a moment and try again.'], 429);
        }
    }
}
