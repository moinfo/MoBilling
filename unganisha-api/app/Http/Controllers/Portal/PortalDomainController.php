<?php

namespace App\Http\Controllers\Portal;

use App\Exceptions\RegistrarApiException;
use App\Http\Controllers\Controller;
use App\Models\Document;
use App\Models\Domain;
use App\Models\DomainTld;
use App\Services\DocumentNumberService;
use App\Services\Registrar\DomainBillingService;
use App\Services\Registrar\DomainRegistrarManager;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class PortalDomainController extends Controller
{
    /** The client's domains + WHMCS-style stats. */
    public function index(Request $request)
    {
        $clientId = $request->user()->client_id;

        $domains = Domain::where('client_id', $clientId)
            ->whereNotIn('status', ['cancelled', 'transferred_out'])
            ->orderBy('name')
            ->get();

        $soonCutoff = now()->addDays(45);

        return response()->json([
            'data' => $domains->map(fn ($d) => [
                'id'             => $d->id,
                'name'           => $d->name,
                'status'         => $d->status,
                'registered_at'  => $d->registered_at?->toDateString(),
                'expires_at'     => $d->expires_at?->toDateString(),
                'auto_renew'     => $d->auto_renew,
                'expiring_soon'  => $d->status === 'active' && $d->expires_at && $d->expires_at->lte($soonCutoff),
                'unmanaged'      => (bool) ($d->meta['unmanaged'] ?? false),
                'ssl_valid'      => $d->meta['ssl_valid'] ?? null,
                'ssl_expires_at' => $d->meta['ssl_expires_at'] ?? null,
            ])->values(),
            'stats' => [
                'active'        => $domains->where('status', 'active')->count(),
                'expired'       => $domains->where('status', 'expired')->count(),
                'expiring_soon' => $domains->filter(fn ($d) => $d->status === 'active' && $d->expires_at && $d->expires_at->lte($soonCutoff))->count(),
                'pending'       => $domains->where('status', 'pending')->count(),
            ],
        ]);
    }

    /** Client-initiated renewal: creates the invoice; registry renew fires on payment. */
    public function renew(Request $request, Domain $domain, DomainBillingService $billing)
    {
        abort_unless($domain->client_id === $request->user()->client_id, 404);

        if ($domain->meta['unmanaged'] ?? false) {
            return response()->json(['message' => 'This domain is renewed manually — please contact us.'], 422);
        }

        $data = $request->validate(['years' => 'required|integer|min:1|max:10']);

        try {
            $document = $billing->createRenewalInvoice($domain, $data['years']);
        } catch (\RuntimeException $e) {
            return response()->json(['message' => 'Renewal is not available for this domain — please contact us.'], 422);
        }

        return response()->json([
            'data'    => ['document_id' => $document->id, 'document_number' => $document->document_number, 'total' => (float) $document->total],
            'message' => "Renewal invoice {$document->document_number} created — pay it to renew instantly.",
        ], 201);
    }

    /** Availability check for self-service register/transfer. */
    public function check(Request $request, DomainRegistrarManager $registrar)
    {
        $data = $request->validate(['name' => 'required|string|max:255|regex:/^[a-z0-9][a-z0-9.-]+\.[a-z.]{2,}$/i']);
        $name = strtolower($data['name']);
        $tenantId = $request->user()->tenant_id;

        $pricing = DomainTld::priceFor($tenantId, strtolower(explode('.', $name, 2)[1] ?? ''));

        try {
            $result = $registrar->driverFor($tenantId)->check($name);
        } catch (RegistrarApiException $e) {
            return response()->json(['message' => 'Could not check availability right now — please try again.'], 422);
        }

        return response()->json([
            'name'      => $name,
            'available' => $result['available'],
            'pricing'   => $pricing ? [
                'register_price' => (float) $pricing->register_price,
                'transfer_price' => (float) $pricing->transfer_price,
                'years_min'      => $pricing->years_min,
                'years_max'      => $pricing->years_max,
            ] : null,
        ]);
    }

    /** Self-service order (register or transfer-in) for the client's own account. */
    public function order(Request $request, DomainRegistrarManager $registrar)
    {
        $user = $request->user();
        $tenantId = $user->tenant_id;

        $data = $request->validate([
            'name'      => ['required', 'string', 'max:255', 'regex:/^[a-z0-9][a-z0-9.-]+\.[a-z.]{2,}$/i', Rule::unique('domains', 'name')],
            'years'     => 'required|integer|min:1|max:10',
            'action'    => 'required|in:register,transfer',
            'auth_info' => 'required_if:action,transfer|nullable|string|max:255',
        ]);

        $name = strtolower($data['name']);
        $tld = strtolower(explode('.', $name, 2)[1] ?? '');
        $pricing = DomainTld::priceFor($tenantId, $tld);
        if (!$pricing) {
            return response()->json(['message' => "We don't currently offer .{$tld} — please contact us."], 422);
        }

        if ($data['action'] === 'register') {
            try {
                $check = $registrar->driverFor($tenantId)->check($name);
                if (!$check['available']) {
                    return response()->json(['message' => "{$name} is not available."], 422);
                }
            } catch (RegistrarApiException) {
                return response()->json(['message' => 'Could not verify availability — please try again.'], 422);
            }
        }

        $unitPrice = $data['action'] === 'register' ? $pricing->register_price : $pricing->transfer_price;
        $total = round($unitPrice * $data['years'], 2);

        [$domain, $document] = DB::transaction(function () use ($data, $name, $tenantId, $user, $total, $unitPrice, $registrar) {
            $document = Document::withoutGlobalScopes()->create([
                'tenant_id'       => $tenantId,
                'client_id'       => $user->client_id,
                'type'            => 'invoice',
                'document_number' => app(DocumentNumberService::class)->generate('invoice', $tenantId),
                'date'            => now()->toDateString(),
                'due_date'        => now()->addDays(7)->toDateString(),
                'subtotal'        => $total,
                'discount_amount' => 0,
                'tax_amount'      => 0,
                'total'           => $total,
                'status'          => 'sent',
                'notes'           => "Domain {$data['action']} (portal order): {$name} ({$data['years']} year(s))",
            ]);

            $document->items()->create([
                'item_type'   => 'service',
                'description' => ucfirst($data['action']) . " domain {$name} — {$data['years']} year(s)",
                'quantity'    => $data['years'],
                'price'       => $unitPrice,
                'tax_percent' => 0,
                'tax_amount'  => 0,
                'total'       => $total,
            ]);

            $domain = Domain::create([
                'tenant_id'            => $tenantId,
                'client_id'            => $user->client_id,
                'registrar_account_id' => $registrar->accountFor($tenantId)->id,
                'name'                 => $name,
                'status'               => 'pending',
                'auto_renew'           => true,
                'epp_auth_info'        => $data['auth_info'] ?? null,
                'meta'                 => [
                    'pending_action'    => $data['action'],
                    'pending_years'     => $data['years'],
                    'order_document_id' => $document->id,
                    'portal_order'      => true,
                ],
            ]);

            return [$domain, $document];
        });

        return response()->json([
            'data'    => ['document_id' => $document->id, 'document_number' => $document->document_number, 'total' => (float) $document->total],
            'message' => "Order created — pay invoice {$document->document_number} to complete the {$data['action']}.",
        ], 201);
    }
}
