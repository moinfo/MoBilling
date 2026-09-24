<?php

namespace App\Http\Controllers;

use App\Exceptions\NameComApiException;
use App\Exceptions\RegistrarApiException;
use App\Models\Domain;
use App\Models\DomainTld;
use App\Models\NameComAuditLog;
use App\Models\NameComSettings;
use App\Services\Registrar\DomainRegistrarManager;
use App\Services\Registrar\NameComPricingService;
use App\Services\Registrar\NameComRegistrationService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Staff side of selling Name.com TLDs: pricing rule/settings, TLD catalog sync (read-only),
 * per-TLD overrides + enable, and the confirmed "Register at Name.com" action.
 * USD costs appear ONLY in these staff endpoints.
 */
class NameComSalesController extends Controller
{
    public function __construct(private NameComPricingService $pricing, private NameComRegistrationService $reg) {}

    private function tenant(): string
    {
        return auth()->user()->tenant_id;
    }

    private function settingsArray(NameComSettings $s): array
    {
        return ['usd_rate' => $s->usd_rate, 'fixed_markup' => $s->fixed_markup, 'auto_register' => $s->auto_register,
            'auto_cap_usd' => $s->auto_cap_usd, 'auto_daily_limit' => $s->auto_daily_limit];
    }

    public function settings(): JsonResponse
    {
        return response()->json(['data' => $this->settingsArray(NameComSettings::forTenant($this->tenant()))]);
    }

    public function saveSettings(Request $request): JsonResponse
    {
        $data = $request->validate([
            'usd_rate'         => 'required|numeric|min:1|max:1000000',
            'fixed_markup'     => 'required|numeric|min:0|max:100000000',
            'auto_register'    => 'required|boolean',
            'auto_cap_usd'     => 'required|numeric|min:0|max:100000',
            'auto_daily_limit' => 'required|integer|min:0|max:1000',
        ]);
        $s = NameComSettings::withoutGlobalScopes()->firstOrNew(['tenant_id' => $this->tenant()]);
        $before = $this->settingsArray(NameComSettings::forTenant($this->tenant()));
        $s->fill($data)->save();

        NameComAuditLog::create(['tenant_id' => $this->tenant(), 'user_id' => auth()->id(), 'action' => 'settings.update',
            'target' => null, 'request' => ['from' => $before, 'to' => $this->settingsArray($s)], 'response_status' => 200]);

        return response()->json(['data' => $this->settingsArray($s), 'message' => 'Name.com settings saved. Use "Apply to all TLDs" to re-price existing rows with the new rate.']);
    }

    private function row(DomainTld $t): array
    {
        return [
            'tld' => $t->tld,
            'usd_register' => $t->usd_register, 'usd_renew' => $t->usd_renew, 'usd_transfer' => $t->usd_transfer,
            'register_price' => (float) $t->register_price, 'renew_price' => (float) $t->renew_price, 'transfer_price' => (float) $t->transfer_price,
            'is_active' => $t->is_active, 'price_overridden' => $t->price_overridden, 'overridden_ops' => $t->overridden_ops ?? [],
            'usd_changed' => $t->usd_changed, 'usd_prev' => $t->usd_prev,
            'synced_at' => $t->usd_synced_at?->toIso8601String(),
        ];
    }

    public function tlds(Request $request): JsonResponse
    {
        $q = DomainTld::where('tenant_id', $this->tenant())->where('registrar', 'namecom');
        $counts = [
            'total'      => (clone $q)->count(),
            'enabled'    => (clone $q)->where('is_active', true)->count(),
            'changed'    => (clone $q)->where('usd_changed', true)->count(),
            'overridden' => (clone $q)->where('price_overridden', true)->count(),
        ];
        if ($s = trim((string) $request->query('search', ''))) $q->where('tld', 'like', '%' . str_replace(['%', '_'], ['\\%', '\\_'], strtolower($s)) . '%');
        match ($request->query('filter')) {
            'enabled' => $q->where('is_active', true), 'disabled' => $q->where('is_active', false),
            'changed' => $q->where('usd_changed', true), 'overridden' => $q->where('price_overridden', true), default => null,
        };
        $page = $q->orderBy('tld')->paginate(min(max((int) $request->query('per_page', 50), 10), 200));

        return response()->json([
            'data' => collect($page->items())->map(fn ($t) => $this->row($t))->values(),
            'meta' => ['current_page' => $page->currentPage(), 'last_page' => $page->lastPage(), 'total' => $page->total()],
            'counts' => $counts,
            'settings' => $this->settingsArray(NameComSettings::forTenant($this->tenant())),
        ]);
    }

    /** Read-only: one paced GET /tldpricing (a few pages). Never deletes or re-enables anything. */
    public function sync(): JsonResponse
    {
        try {
            $driver = app(DomainRegistrarManager::class)->namecomFor($this->tenant());
            $r = $this->pricing->sync($this->tenant(), $driver);
        } catch (NameComApiException | RegistrarApiException $e) {
            return response()->json(['message' => $e instanceof RegistrarApiException ? preg_replace('/^Registrar \S+ failed: /', '', $e->getMessage()) : $e->getMessage()], 422);
        }
        NameComAuditLog::create(['tenant_id' => $this->tenant(), 'user_id' => auth()->id(), 'action' => 'tlds.sync', 'request' => $r, 'response_status' => 200]);

        return response()->json(['data' => $r, 'message' => "Synced {$r['total']} TLDs: {$r['created']} new, {$r['changed']} with a changed USD cost."]);
    }

    public function updateTld(Request $request, string $tld): JsonResponse
    {
        $t = DomainTld::where('tenant_id', $this->tenant())->where('registrar', 'namecom')->where('tld', strtolower($tld))->firstOrFail();
        $data = $request->validate([
            'register_price' => 'sometimes|numeric|min:0|max:100000000',
            'renew_price'    => 'sometimes|numeric|min:0|max:100000000',
            'transfer_price' => 'sometimes|nullable|numeric|min:0|max:100000000',
            'is_active'      => 'sometimes|boolean',
            'reset_override' => 'sometimes|boolean',
        ]);

        $upd = [];
        if (!empty($data['reset_override'])) {
            $p = NameComPricingService::pricesFor($t->usd_register, $t->usd_renew, $t->usd_transfer, NameComSettings::forTenant($this->tenant()));
            $upd = ['register_price' => $p['register'] ?? 0, 'renew_price' => $p['renew'] ?? 0, 'transfer_price' => $p['transfer'] ?? 0, 'price_overridden' => false, 'overridden_ops' => null];
        } else {
            $ops = $t->overridden_ops ?? [];
            foreach (['register', 'renew', 'transfer'] as $op) {
                $k = "{$op}_price";
                if (!array_key_exists($k, $data)) continue;
                $v = round((float) ($data[$k] ?? 0));
                if ($v !== (float) $t->{$k}) { $upd[$k] = $v; $ops[] = $op; } // only prices staff actually changed become manual
            }
            $upd['overridden_ops'] = array_values(array_unique($ops));
            $upd['price_overridden'] = !empty($upd['overridden_ops']);
        }
        if (array_key_exists('is_active', $data)) $upd['is_active'] = (bool) $data['is_active'];

        $after = array_merge($t->only(['register_price', 'renew_price', 'transfer_price', 'is_active']), $upd);
        if (!empty($after['is_active'])) {
            if ($t->usd_register === null) return response()->json(['message' => "Name.com does not offer registrations for .{$t->tld}; it cannot be enabled."], 422);
            if ((float) $after['register_price'] <= 0 || (float) $after['renew_price'] <= 0) {
                return response()->json(['message' => 'Set a register and renew price above zero before enabling this TLD.'], 422);
            }
        }
        $t->update($upd);
        NameComAuditLog::create(['tenant_id' => $this->tenant(), 'user_id' => auth()->id(), 'action' => 'tld.update', 'target' => $t->tld, 'request' => $upd, 'response_status' => 200]);

        return response()->json(['data' => $this->row($t->fresh()), 'message' => ".{$t->tld} updated."]);
    }

    /** Acknowledge the "USD cost changed" flags (all, or the given TLDs). */
    public function ackChanges(Request $request): JsonResponse
    {
        $data = $request->validate(['tlds' => 'sometimes|array|max:500', 'tlds.*' => 'string|max:63']);
        $q = DomainTld::where('tenant_id', $this->tenant())->where('registrar', 'namecom')->where('usd_changed', true);
        if (!empty($data['tlds'])) $q->whereIn('tld', array_map('strtolower', $data['tlds']));
        $n = $q->update(['usd_changed' => false]);

        return response()->json(['message' => "$n flag(s) cleared."]);
    }

    /** Re-price every non-overridden Name.com TLD with the current rate/markup. */
    public function recompute(): JsonResponse
    {
        $n = $this->pricing->recompute($this->tenant());
        NameComAuditLog::create(['tenant_id' => $this->tenant(), 'user_id' => auth()->id(), 'action' => 'tlds.recompute', 'request' => ['rows' => $n], 'response_status' => 200]);

        return response()->json(['message' => "$n TLD price(s) recalculated (manual overrides were kept)."]);
    }

    // ── registration queue ──

    public function registrationPreview(Domain $domain): JsonResponse
    {
        if (!NameComRegistrationService::isQueued($domain)) return response()->json(['message' => 'This domain is not waiting for registration at Name.com.'], 422);
        return response()->json(['data' => $this->reg->preview($domain)]);
    }

    public function register(Request $request, Domain $domain): JsonResponse
    {
        $data = $request->validate(['confirm' => 'required|accepted', 'usd_cost' => 'required|numeric|min:0']);
        try {
            $d = $this->reg->register($domain, ['by_user' => auth()->id()], 'manual', (float) $data['usd_cost']);
        } catch (\DomainException | \InvalidArgumentException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        } catch (NameComApiException | RegistrarApiException $e) {
            return response()->json(['message' => $e instanceof RegistrarApiException ? preg_replace('/^Registrar \S+ failed: /', '', $e->getMessage()) : $e->getMessage()], 422);
        }

        return response()->json(['data' => $d->load('client:id,name'), 'message' => "{$d->name} registered at Name.com. The client was notified that it is ready."]);
    }
}
