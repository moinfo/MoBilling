<?php

namespace App\Http\Controllers;

use App\Exceptions\NameComApiException;
use App\Exceptions\RegistrarApiException;
use App\Models\Domain;
use App\Models\NameComAccount;
use App\Models\NameComAuditLog;
use App\Services\Registrar\NameComDomainService;
use App\Services\Registrar\NameComDriver;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Staff side of the Name.com integration (nameserver management + linking only).
 * Credentials are per tenant and write-only: the token never appears in a response.
 */
class NameComController extends Controller
{
    public function __construct(private NameComDomainService $svc) {}

    public function account(): JsonResponse
    {
        $a = NameComAccount::first();
        return response()->json(['data' => $a?->toSafeArray()]);
    }

    /** Create or rotate credentials (token required the first time; omit it to keep the stored one). */
    public function saveAccount(Request $request): JsonResponse
    {
        $existing = NameComAccount::first();
        $data = $request->validate([
            'username'   => ['required', 'string', 'max:100', 'regex:/^\S+$/'],
            'token'      => [$existing ? 'nullable' : 'required', 'string', 'min:10', 'max:512', 'regex:/^\S+$/'],
            'is_sandbox' => 'nullable|boolean',
        ]);

        $token = !empty($data['token']) ? $data['token'] : ($existing?->token);
        $probe = new NameComAccount(['username' => $data['username'], 'token' => $token, 'is_sandbox' => (bool) ($data['is_sandbox'] ?? false)]);
        $probe->tenant_id = auth()->user()->tenant_id;

        try {
            (new NameComDriver($probe))->verify();
        } catch (NameComApiException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        $account = $existing ?? new NameComAccount();
        $account->tenant_id = auth()->user()->tenant_id;
        $account->username = $data['username'];
        $account->is_sandbox = (bool) ($data['is_sandbox'] ?? false);
        if (!empty($data['token'])) {
            $account->token = $data['token'];
            $account->token_hint = substr($data['token'], -4);
        }
        $account->status = 'active';
        $account->status_message = null;
        $account->last_verified_at = now();
        $account->save();

        $this->audit($account, !empty($data['token']) ? ($existing ? 'account.rotate_token' : 'account.create') : 'account.update', $account->username);

        return response()->json(['data' => $account->toSafeArray(), 'message' => 'Name.com connected.']);
    }

    public function deleteAccount(): JsonResponse
    {
        $a = NameComAccount::first();
        if ($a) {
            $this->audit($a, 'account.delete', $a->username);
            $a->delete(); // local credentials only; nothing is touched at Name.com
        }
        return response()->json(['message' => 'Name.com credentials removed from MoBilling. Nothing was changed at Name.com.']);
    }

    /** Read-only connectivity check. */
    public function test(): JsonResponse
    {
        $a = NameComAccount::first();
        if (!$a) return response()->json(['message' => 'Name.com is not connected yet.'], 422);
        try {
            (new NameComDriver($a))->verify();
        } catch (NameComApiException $e) {
            if ($e->httpStatus === 401 || $e->httpStatus === 403) {
                $a->update(['status' => 'invalid', 'status_message' => mb_substr($e->getMessage(), 0, 250), 'last_verified_at' => now()]);
            }
            return response()->json(['message' => $e->getMessage()], 422);
        }
        $a->update(['status' => 'active', 'status_message' => null, 'last_verified_at' => now()]);
        return response()->json(['data' => $a->toSafeArray(), 'message' => 'Connection OK.']);
    }

    /** Read-only list of the Name.com account's domains and whether MoBilling already has them. */
    public function domains(): JsonResponse
    {
        try {
            $remote = app(\App\Services\Registrar\DomainRegistrarManager::class)->namecomFor(auth()->user()->tenant_id)->listDomains();
        } catch (NameComApiException | RegistrarApiException $e) {
            return response()->json(['message' => $this->msg($e)], 422);
        }

        $names = collect($remote)->pluck('domainName')->map(fn ($n) => strtolower((string) $n))->filter()->values();
        $ours = Domain::with('client:id,name')->whereIn('name', $names->all())
            ->whereNotIn('status', ['cancelled', 'transferred_out'])->get()->keyBy('name');

        $rows = collect($remote)->map(function ($d) use ($ours) {
            $name = strtolower((string) ($d['domainName'] ?? ''));
            $mine = $ours->get($name);
            return [
                'name'         => $name,
                'expires_at'   => substr((string) ($d['expireDate'] ?? ''), 0, 10) ?: null,
                'locked'       => $d['locked'] ?? null,
                'nameservers'  => NameComDriver::extractNameservers($d),
                'domain_id'    => $mine?->id,
                'client_id'    => $mine?->client_id,
                'client_name'  => $mine?->client?->name,
                'linked'       => $mine ? NameComDomainService::isLinked($mine) : false,
                'in_mobilling' => (bool) $mine,
                'fred_managed' => $mine ? ($mine->registrar_account_id && !($mine->meta['unmanaged'] ?? false)) : false,
            ];
        })->sortBy('name')->values();

        return response()->json(['data' => $rows]);
    }

    public function link(Request $request): JsonResponse
    {
        $data = $request->validate(['domain_name' => 'required|string|max:253', 'client_id' => 'required|uuid']);
        try {
            $domain = $this->svc->link(auth()->user()->tenant_id, $data['domain_name'], $data['client_id'], ['by_user' => auth()->id()]);
        } catch (\InvalidArgumentException | \DomainException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        } catch (NameComApiException | RegistrarApiException $e) {
            return response()->json(['message' => $this->msg($e)], 422);
        }

        return response()->json(['data' => $domain->load('client:id,name'), 'message' => "{$domain->name} linked to Name.com."]);
    }

    public function refresh(Domain $domain): JsonResponse
    {
        abort_unless(NameComDomainService::isLinked($domain), 422, 'This domain is not linked to Name.com.');
        try {
            $d = $this->svc->sync($domain);
        } catch (NameComApiException | RegistrarApiException $e) {
            return response()->json(['message' => $this->msg($e)], 422);
        }
        return response()->json(['data' => $d, 'message' => 'Refreshed from Name.com.']);
    }

    private function msg(\Throwable $e): string
    {
        return $e instanceof RegistrarApiException ? preg_replace('/^Registrar \S+ failed: /', '', $e->getMessage()) : $e->getMessage();
    }

    private function audit(NameComAccount $a, string $action, ?string $target): void
    {
        NameComAuditLog::create([
            'tenant_id' => $a->tenant_id, 'user_id' => auth()->id(), 'namecom_account_id' => $a->id,
            'action' => $action, 'target' => $target, 'request' => ['sandbox' => $a->is_sandbox], 'response_status' => 200,
        ]);
    }
}
