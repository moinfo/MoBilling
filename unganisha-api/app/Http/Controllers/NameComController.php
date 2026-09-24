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

    // ── credentials (several per tenant; the token is write-only) ──

    private function tenantId(): string
    {
        return auth()->user()->tenant_id;
    }

    /** @return \Illuminate\Support\Collection<int, NameComAccount> default first */
    private function accounts()
    {
        return NameComAccount::orderByDesc('is_default')->orderBy('created_at')->get();
    }

    /** Linked-domain counts per account (legacy links without account_id belong to the default account). */
    private function linkedCounts($accounts): array
    {
        $default = $accounts->firstWhere('is_default', true) ?? $accounts->first();
        $counts = [];
        Domain::whereNotNull('meta->namecom')->whereNotIn('status', ['cancelled', 'transferred_out'])->get(['id', 'meta'])->each(function ($d) use (&$counts, $default) {
            $id = $d->meta['namecom']['account_id'] ?? $default?->id;
            if ($id) $counts[$id] = ($counts[$id] ?? 0) + 1;
        });
        return $counts;
    }

    public function accountList(): JsonResponse
    {
        $accounts = $this->accounts();
        $counts = $this->linkedCounts($accounts);
        return response()->json(['data' => $accounts->map(fn ($a) => $a->toSafeArray() + ['linked_domains' => $counts[$a->id] ?? 0])->values()]);
    }

    /** Label/id/status only (no username or token): enough for the import and registration pickers. */
    public function accountOptions(): JsonResponse
    {
        return response()->json(['data' => $this->accounts()->map(fn ($a) => [
            'id' => $a->id, 'label' => $a->displayLabel(), 'username' => $a->username, 'is_default' => (bool) $a->is_default, 'status' => $a->status,
        ])->values()]);
    }

    public function storeAccount(Request $request): JsonResponse
    {
        $data = $request->validate([
            'label'      => ['required', 'string', 'min:2', 'max:60'],
            'username'   => ['required', 'string', 'max:100', 'regex:/^\S+$/'],
            'token'      => ['required', 'string', 'min:10', 'max:512', 'regex:/^\S+$/'],
            'is_sandbox' => 'nullable|boolean',
            'is_default' => 'nullable|boolean',
        ]);
        return $this->persist(null, $data);
    }

    public function updateAccount(Request $request, string $account): JsonResponse
    {
        $a = NameComAccount::findOrFail($account);
        $data = $request->validate([
            'label'      => ['sometimes', 'string', 'min:2', 'max:60'],
            'username'   => ['sometimes', 'string', 'max:100', 'regex:/^\S+$/'],
            'token'      => ['nullable', 'string', 'min:10', 'max:512', 'regex:/^\S+$/'],
            'is_sandbox' => 'nullable|boolean',
            'is_default' => 'nullable|boolean',
        ]);
        return $this->persist($a, $data);
    }

    /** Create/update/rotate one credential set. The change is only stored after Name.com accepted the credentials. */
    private function persist(?NameComAccount $existing, array $data): JsonResponse
    {
        $tenantId = $this->tenantId();
        $others = NameComAccount::when($existing, fn ($q) => $q->where('id', '!=', $existing->id))->get();

        $label = trim($data['label'] ?? $existing?->label ?? '');
        if ($label === '') $label = $data['username'] ?? $existing?->username ?? 'Account';
        $username = $data['username'] ?? $existing?->username;
        $sandbox = array_key_exists('is_sandbox', $data) ? (bool) $data['is_sandbox'] : (bool) ($existing?->is_sandbox ?? false);

        if ($others->contains(fn ($o) => mb_strtolower($o->displayLabel()) === mb_strtolower($label))) {
            return response()->json(['message' => "You already have an account labelled \"{$label}\". Use a different label."], 422);
        }
        if ($others->contains(fn ($o) => strtolower($o->username) === strtolower($username) && (bool) $o->is_sandbox === $sandbox)) {
            return response()->json(['message' => "The Name.com username \"{$username}\" is already added."], 422);
        }

        $token = !empty($data['token']) ? $data['token'] : $existing?->token;
        $probe = new NameComAccount(['username' => $username, 'token' => $token, 'is_sandbox' => $sandbox]);
        $probe->tenant_id = $tenantId;
        try {
            (new NameComDriver($probe))->verify();
        } catch (NameComApiException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        $isNew = !$existing;
        $account = $existing ?? new NameComAccount();
        $account->tenant_id = $tenantId;
        $account->label = $label;
        $account->username = $username;
        $account->is_sandbox = $sandbox;
        if (!empty($data['token'])) {
            $account->token = $data['token'];
            $account->token_hint = substr($data['token'], -4);
        }
        $account->status = 'active';
        $account->status_message = null;
        $account->last_verified_at = now();
        $wantDefault = !empty($data['is_default']) || ($isNew && $others->isEmpty());
        \DB::transaction(function () use ($account, $wantDefault, $others) {
            if ($wantDefault) {
                NameComAccount::where('tenant_id', $account->tenant_id)->where('is_default', true)->update(['is_default' => false]);
                $account->is_default = true;
            }
            $account->save();
        });

        $this->audit($account, !empty($data['token']) ? ($isNew ? 'account.create' : 'account.rotate_token') : 'account.update', $account->username);

        return response()->json(['data' => $account->toSafeArray(), 'message' => $isNew ? "Name.com account \"{$label}\" added." : "Name.com account \"{$label}\" saved."]);
    }

    public function destroyAccount(Request $request, string $account): JsonResponse
    {
        $a = NameComAccount::findOrFail($account);
        $accounts = $this->accounts();
        $used = $this->linkedCounts($accounts)[$a->id] ?? 0;
        if ($used > 0 && !$request->boolean('confirm_linked')) {
            return response()->json(['message' => "{$used} linked domain(s) use this account. Removing it means their nameservers fall back to the default account and may not be manageable. Confirm to remove anyway.", 'linked_domains' => $used], 409);
        }
        $this->audit($a, 'account.delete', $a->username);
        $wasDefault = (bool) $a->is_default;
        $a->delete(); // local credentials only; nothing is touched at Name.com
        if ($wasDefault) {
            $next = $this->accounts()->first();
            if ($next) $next->update(['is_default' => true]);
        }
        return response()->json(['message' => 'Name.com account removed from MoBilling. Nothing was changed at Name.com.']);
    }

    public function testAccount(string $account): JsonResponse
    {
        return $this->runTest(NameComAccount::findOrFail($account));
    }

    private function runTest(NameComAccount $a): JsonResponse
    {
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

    // Legacy single-account endpoints: act on the default account.
    public function account(): JsonResponse
    {
        return response()->json(['data' => NameComAccount::defaultFor($this->tenantId())?->toSafeArray()]);
    }

    public function saveAccount(Request $request): JsonResponse
    {
        $existing = NameComAccount::defaultFor($this->tenantId());
        $data = $request->validate([
            'username'   => ['required', 'string', 'max:100', 'regex:/^\S+$/'],
            'token'      => [$existing ? 'nullable' : 'required', 'string', 'min:10', 'max:512', 'regex:/^\S+$/'],
            'is_sandbox' => 'nullable|boolean',
        ]);
        return $this->persist($existing, $data);
    }

    public function deleteAccount(Request $request): JsonResponse
    {
        $a = NameComAccount::defaultFor($this->tenantId());
        return $a ? $this->destroyAccount($request, $a->id) : response()->json(['message' => 'Nothing to remove.']);
    }

    public function test(): JsonResponse
    {
        $a = NameComAccount::defaultFor($this->tenantId());
        if (!$a) return response()->json(['message' => 'Name.com is not connected yet.'], 422);
        return $this->runTest($a);
    }

    // ── import / link ──

    /** Accounts to read from: one (?account_id=), or all of them (?account_id=all / omitted). */
    private function selectedAccounts(Request $request)
    {
        $id = (string) $request->query('account_id', 'all');
        $all = $this->accounts();
        if ($id === '' || $id === 'all') return $all;
        return $all->where('id', $id)->values();
    }

    /**
     * Read-only list of the domains in one Name.com account (or all accounts, aggregated) and whether MoBilling
     * already has them. A failing account is reported in `errors` without hiding the others.
     */
    public function domains(Request $request): JsonResponse
    {
        $accounts = $this->selectedAccounts($request);
        if ($accounts->isEmpty()) return response()->json(['message' => 'Name.com is not connected. Add your Name.com API credentials under Domains > Name.com.'], 422);

        $remote = []; // name => [info, account]
        $errors = [];
        foreach ($accounts as $acc) {
            try {
                $list = app(\App\Services\Registrar\DomainRegistrarManager::class)->namecomFor($this->tenantId(), $acc->id)->listDomains();
            } catch (NameComApiException | RegistrarApiException $e) {
                $errors[] = ['account_id' => $acc->id, 'account_label' => $acc->displayLabel(), 'message' => $this->msg($e)];
                continue;
            }
            foreach ($list as $d) {
                $n = strtolower((string) ($d['domainName'] ?? ''));
                if ($n !== '' && !isset($remote[$n])) $remote[$n] = ['info' => $d, 'account' => $acc];
            }
        }
        if ($errors && !$remote && count($errors) === $accounts->count()) {
            return response()->json(['message' => $errors[0]['message'], 'errors' => $errors], 422);
        }

        $ours = Domain::with('client:id,name')->whereIn('name', array_keys($remote))
            ->whereNotIn('status', ['cancelled', 'transferred_out'])->get()->keyBy('name');
        $labels = $this->accounts()->keyBy('id');
        $default = $this->accounts()->first();

        $rows = collect($remote)->map(function ($r, $name) use ($ours, $labels, $default) {
            $d = $r['info'];
            $mine = $ours->get($name);
            $linked = $mine ? NameComDomainService::isLinked($mine) : false;
            $linkedAcc = $linked ? ($labels->get($mine->meta['namecom']['account_id'] ?? null) ?? $default) : null;
            return [
                'name'         => $name,
                'expires_at'   => substr((string) ($d['expireDate'] ?? ''), 0, 10) ?: null,
                'locked'       => $d['locked'] ?? null,
                'nameservers'  => NameComDriver::extractNameservers($d),
                'account_id'   => $r['account']->id,
                'account_label' => $r['account']->displayLabel(),
                'domain_id'    => $mine?->id,
                'client_id'    => $mine?->client_id,
                'client_name'  => $mine?->client?->name,
                'linked'       => $linked,
                'linked_account_label' => $linkedAcc?->displayLabel(),
                'in_mobilling' => (bool) $mine,
                'fred_managed' => $mine ? ($mine->registrar_account_id && !($mine->meta['unmanaged'] ?? false)) : false,
            ];
        })->sortBy('name')->values();

        return response()->json(['data' => $rows, 'errors' => $errors]);
    }

    public function link(Request $request): JsonResponse
    {
        $data = $request->validate(['domain_name' => 'required|string|max:253', 'client_id' => 'required|uuid', 'account_id' => 'nullable|uuid']);
        try {
            $domain = $this->svc->link($this->tenantId(), $data['domain_name'], $data['client_id'], ['by_user' => auth()->id()], $data['account_id'] ?? null);
        } catch (\InvalidArgumentException | \DomainException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        } catch (NameComApiException | RegistrarApiException $e) {
            return response()->json(['message' => $this->msg($e)], 422);
        }

        return response()->json(['data' => $domain->load('client:id,name'), 'message' => "{$domain->name} linked to Name.com."]);
    }

    /**
     * Bulk helper: link domains that already exist in MoBilling (same tenant, not linked, not .tz-registry managed)
     * to the client already on that row. The client is taken from the MoBilling row, never from the browser.
     * dry_run=true (default) only reports what WOULD happen; nothing changes without confirm=true.
     */
    public function linkMatched(Request $request): JsonResponse
    {
        $data = $request->validate([
            'items'              => 'required|array|min:1|max:50',
            'items.*.domain_name' => 'required|string|max:253',
            'items.*.account_id' => 'required|uuid',
            'confirm'            => 'sometimes|boolean',
        ]);
        $confirm = (bool) ($data['confirm'] ?? false);

        $results = [];
        foreach ($data['items'] as $it) {
            $name = strtolower(trim($it['domain_name']));
            $row = Domain::where('name', $name)->whereNotIn('status', ['cancelled', 'transferred_out'])->first();
            if (!$row) { $results[] = ['name' => $name, 'status' => 'new', 'message' => 'No matching domain in MoBilling.']; continue; }
            if ($row->registrar_account_id && !($row->meta['unmanaged'] ?? false)) { $results[] = ['name' => $name, 'status' => 'skipped', 'message' => 'Managed through the .tz registry.']; continue; }
            if (NameComDomainService::isLinked($row)) { $results[] = ['name' => $name, 'status' => 'skipped', 'message' => 'Already linked.']; continue; }
            if (!$row->client_id) { $results[] = ['name' => $name, 'status' => 'new', 'message' => 'The MoBilling domain has no client.']; continue; }
            if (!$confirm) { $results[] = ['name' => $name, 'status' => 'ready', 'client_id' => $row->client_id, 'client_name' => $row->client?->name]; continue; }
            try {
                $d = $this->svc->link($this->tenantId(), $name, $row->client_id, ['by_user' => auth()->id(), 'bulk' => true], $it['account_id']);
                $results[] = ['name' => $name, 'status' => 'linked', 'client_id' => $d->client_id];
            } catch (\InvalidArgumentException | \DomainException | NameComApiException | RegistrarApiException $e) {
                $results[] = ['name' => $name, 'status' => 'failed', 'message' => $this->msg($e)];
            }
        }

        $linked = collect($results)->where('status', 'linked')->count();
        return response()->json(['data' => $results, 'message' => $confirm ? "{$linked} domain(s) linked." : 'Preview only - nothing was changed.']);
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
