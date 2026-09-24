<?php

namespace App\Services\Linode;

use App\Models\Client;
use App\Models\ClientSubscription;
use App\Models\Document;
use App\Models\LinodeAuditLog;
use App\Models\LinodeResource;
use App\Models\ProductService;
use App\Models\RecurringInvoiceLog;
use App\Services\DocumentNumberService;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Billing-only link between a synced Linode server and a ClientSubscription.
 * NOTHING here ever calls Linode: it only writes MoBilling rows. All queries go
 * through tenant-scoped models (the acting user's tenant).
 */
class LinodeBilling
{
    public const CYCLE_MONTHS = ['monthly' => 1, 'quarterly' => 3, 'half_yearly' => 6, 'yearly' => 12];
    /** Statuses that mean "this server is already being billed". */
    public const LIVE = ['pending', 'active', 'suspended'];

    public static function addCycle(Carbon $d, string $cycle): Carbon
    {
        // Same arithmetic the recurring engine uses (->add('N month(s)')).
        return $d->copy()->addMonths(self::CYCLE_MONTHS[$cycle]);
    }

    public static function subCycle(Carbon $d, string $cycle): Carbon
    {
        return $d->copy()->subMonths(self::CYCLE_MONTHS[$cycle]);
    }

    /** Linode-type products staff can bill a server with. */
    public function products()
    {
        return ProductService::where('provisioning_type', 'linode')->where('is_active', true)
            ->whereIn('billing_cycle', array_keys(self::CYCLE_MONTHS))->whereNull('invoice_day_of_month')
            ->orderBy('name')->get(['id', 'name', 'price', 'tax_percent', 'billing_cycle', 'category']);
    }

    /**
     * @param array{client_id:string,product_service_id:string,amount:float|int|string,start_date:string,expire_date?:?string,
     *              mode:string,label?:?string,billing_cycle?:?string} $d  mode = paid_outside | invoice_now
     * @return array{subscription:ClientSubscription,document:?Document}
     */
    public function bill(LinodeResource $resource, array $d): array
    {
        return DB::transaction(function () use ($resource, $d) {
            $r = LinodeResource::whereKey($resource->id)->lockForUpdate()->firstOrFail();
            if ($r->type !== 'instance') {
                throw new \DomainException('Only Linode servers can be billed here.');
            }
            $this->assertNotBilled($r);

            $client = Client::find($d['client_id']);
            if (!$client) {
                throw new \DomainException('That client does not belong to your business.');
            }
            $product = ProductService::where('id', $d['product_service_id'])->where('provisioning_type', 'linode')->where('is_active', true)->first();
            if (!$product) {
                throw new \DomainException('Choose an active "Linode Server" product.');
            }
            $cycle = $product->billing_cycle;
            if (!isset(self::CYCLE_MONTHS[$cycle]) || $product->invoice_day_of_month) {
                throw new \DomainException('The product must bill monthly, quarterly, half-yearly or yearly.');
            }
            if (!empty($d['billing_cycle']) && $d['billing_cycle'] !== $cycle) {
                throw new \DomainException("This product bills {$cycle}. Pick a Linode product with the {$d['billing_cycle']} cycle instead.");
            }
            $amount = round((float) $d['amount'], 2);
            if ($amount <= 0) {
                throw new \DomainException('Enter a billing amount greater than zero.');
            }

            $start = Carbon::parse($d['start_date'])->startOfDay();
            $paidOutside = $d['mode'] === 'paid_outside';
            $expire = !empty($d['expire_date']) ? Carbon::parse($d['expire_date'])->startOfDay() : self::addCycle($start, $cycle);
            if ($paidOutside && $expire->lte($start)) {
                throw new \DomainException('The expiry date must be after the start date.');
            }

            // The recurring engine walks start_date forward in whole cycles; anchor it one cycle before the
            // expiry (exactly what the WHMCS import does) so the walk lands on the renewal date.
            $anchor = $paidOutside ? self::subCycle($expire, $cycle) : $start;

            // RecurringInvoiceLog is unique per (client, product, next_bill_date): two servers of the same client
            // on the same product with the same anchor would collide and the second would never be invoiced.
            $clash = ClientSubscription::where('client_id', $client->id)->where('product_service_id', $product->id)
                ->whereDate('start_date', $anchor->toDateString())->whereIn('status', self::LIVE)->exists();
            if ($clash) {
                throw new \DomainException('This client already has a subscription on this product with the same billing date. Use a different start date or a separate product so both renewals are invoiced.');
            }

            $label = trim((string) ($d['label'] ?? '')) ?: trim($r->label . ' ' . ($r->ipv4[0] ?? ''));
            $meta = array_filter([
                'billing_source' => 'linode', 'linode_resource_id' => $r->id, 'linode_instance_id' => $r->remote_id,
                'linode_ipv4' => $r->ipv4[0] ?? null, 'linode_region' => $r->region, 'linode_plan' => $r->plan,
                'paid_outside' => $paidOutside ?: null,
                'price_override' => abs($amount - (float) $product->price) > 0.004 ?: null,
                'original_start_date' => $paidOutside && !$anchor->equalTo($start) ? $start->toDateString() : null,
                'created_by' => auth()->id(),
            ], fn ($v) => $v !== null);

            $sub = ClientSubscription::create([
                'client_id' => $client->id, 'product_service_id' => $product->id, 'label' => $label, 'quantity' => 1,
                'start_date' => $anchor->toDateString(),
                // paid_outside: current period is settled -> active until expire_date.
                // invoice_now: pending until the invoice is paid; SubscriptionActivationService then sets
                // expire_date = start + 1 cycle (pre-setting it would double-count the period).
                'expire_date' => $paidOutside ? $expire->toDateString() : null,
                'status' => $paidOutside ? 'active' : 'pending',
                'recurring_amount' => $amount, 'first_payment_amount' => $paidOutside ? null : $amount,
                'payment_method' => $paidOutside ? 'outside_system' : null,
                'metadata' => $meta,
            ]);

            $document = null;
            if ($paidOutside) {
                // No invoice. If the anchor is today/future the engine would treat it as "due now": pre-mark that
                // cycle as handled so only the NEXT cycle gets invoiced.
                if ($anchor->gte(Carbon::today())) {
                    RecurringInvoiceLog::firstOrCreate(
                        ['client_id' => $client->id, 'product_service_id' => $product->id, 'next_bill_date' => $anchor->toDateString()],
                        ['client_subscription_id' => $sub->id, 'document_id' => null, 'invoice_created_at' => null, 'reminders_sent' => []]
                    );
                }
            } else {
                $document = $this->createInvoice($client, $product, $sub, $amount, $start, self::addCycle($start, $cycle), $label);
            }

            $r->update(['client_id' => $client->id, 'client_subscription_id' => $sub->id]);
            $this->audit($r, 'resource.bill', [
                'client_id' => $client->id, 'client_subscription_id' => $sub->id, 'product_service_id' => $product->id,
                'amount' => $amount, 'cycle' => $cycle, 'mode' => $d['mode'], 'start_date' => $anchor->toDateString(),
                'expire_date' => $paidOutside ? $expire->toDateString() : null, 'document_id' => $document?->id,
            ]);

            return ['subscription' => $sub, 'document' => $document];
        });
    }

    /** Same document shape the staff "new subscription" flow builds (status sent, product tax applied). */
    private function createInvoice(Client $client, ProductService $product, ClientSubscription $sub, float $amount, Carbon $from, Carbon $to, string $label): Document
    {
        $tax = round($amount * ((float) ($product->tax_percent ?? 0) / 100), 2);
        $total = round($amount + $tax, 2);
        $due = $from->gte(Carbon::today()) ? $from : Carbon::today()->addDays(7);

        $doc = Document::create([
            'client_id' => $client->id, 'type' => 'invoice',
            'document_number' => app(DocumentNumberService::class)->generate('invoice', auth()->user()->tenant_id),
            'date' => now()->format('Y-m-d'), 'due_date' => $due->format('Y-m-d'),
            'subtotal' => $amount, 'discount_amount' => 0, 'tax_amount' => $tax, 'total' => $total,
            'notes' => 'Invoice for Linode server subscription', 'status' => 'sent', 'created_by' => auth()->id(),
        ]);
        $doc->items()->create([
            'product_service_id' => $product->id, 'item_type' => $product->type,
            'description' => $product->name . ' — ' . $label, 'quantity' => 1, 'price' => $amount,
            'discount_type' => 'percent', 'discount_value' => 0, 'tax_percent' => $product->tax_percent ?? 0,
            'tax_amount' => $tax, 'total' => $total, 'unit' => $product->unit,
            'service_from' => $from->format('Y-m-d'), 'service_to' => $to->copy()->subDay()->format('Y-m-d'),
        ]);
        // Covers this cycle for the engine AND lets payment activate the subscription.
        RecurringInvoiceLog::create([
            'client_id' => $client->id, 'product_service_id' => $product->id, 'client_subscription_id' => $sub->id,
            'document_id' => $doc->id, 'next_bill_date' => $from->format('Y-m-d'), 'invoice_created_at' => now(), 'reminders_sent' => [],
        ]);

        return $doc;
    }

    public function link(LinodeResource $resource, string $subscriptionId): ClientSubscription
    {
        return DB::transaction(function () use ($resource, $subscriptionId) {
            $r = LinodeResource::whereKey($resource->id)->lockForUpdate()->firstOrFail();
            if ($r->type !== 'instance') {
                throw new \DomainException('Only Linode servers can be linked to a subscription.');
            }
            $this->assertNotBilled($r);
            $sub = ClientSubscription::where('id', $subscriptionId)->whereIn('status', self::LIVE)->first();
            if (!$sub) {
                throw new \DomainException('Subscription not found (or it is cancelled/expired).');
            }
            if ($r->client_id && $r->client_id !== $sub->client_id) {
                throw new \DomainException('That subscription belongs to a different client than the one this server is mapped to.');
            }
            if (LinodeResource::where('client_subscription_id', $sub->id)->where('id', '!=', $r->id)->exists()) {
                throw new \DomainException('That subscription is already linked to another server.');
            }
            $meta = $sub->metadata ?? [];
            $meta += ['linode_resource_id' => $r->id, 'linode_instance_id' => $r->remote_id, 'linode_ipv4' => $r->ipv4[0] ?? null, 'linode_region' => $r->region, 'linode_plan' => $r->plan];
            $sub->update(['metadata' => $meta]);
            $r->update(['client_id' => $sub->client_id, 'client_subscription_id' => $sub->id]);
            $this->audit($r, 'resource.link_subscription', ['client_subscription_id' => $sub->id, 'client_id' => $sub->client_id]);

            return $sub;
        });
    }

    public function unlink(LinodeResource $resource): void
    {
        DB::transaction(function () use ($resource) {
            $r = LinodeResource::whereKey($resource->id)->lockForUpdate()->firstOrFail();
            $subId = $r->client_subscription_id;
            if (!$subId) {
                return;
            }
            // Only the link is removed: the subscription keeps billing and nothing changes at Linode.
            $r->update(['client_subscription_id' => null]);
            $this->audit($r, 'resource.unlink_subscription', ['client_subscription_id' => $subId]);
        });
    }

    /** Staff-facing billing summary for one server (used by the Servers tab). */
    public function summary(?ClientSubscription $sub, ?RecurringInvoiceLog $log): ?array
    {
        if (!$sub) {
            return null;
        }
        $product = $sub->productService;
        $doc = $log?->document;
        $next = $this->nextBillDate($sub);
        $state = match (true) {
            in_array($sub->status, ['cancelled', 'terminated', 'expired']) => 'expired',
            $sub->status === 'suspended' => 'suspended',
            $sub->status === 'pending' => 'pending',
            $sub->expire_date && $sub->expire_date->lt(Carbon::today()) => 'expired',
            default => 'active',
        };

        return [
            'id' => $sub->id, 'state' => $state, 'status' => $sub->status, 'label' => $sub->label,
            'product_name' => $product?->name, 'billing_cycle' => $product?->billing_cycle,
            'amount' => $sub->recurring_amount !== null ? (float) $sub->recurring_amount : (float) ($product?->price ?? 0),
            'start_date' => $sub->start_date?->toDateString(), 'expire_date' => $sub->expire_date?->toDateString(),
            'next_invoice_date' => $next?->toDateString(),
            'latest_invoice' => $doc ? ['id' => $doc->id, 'number' => $doc->document_number, 'status' => $doc->status, 'due_date' => $doc->due_date?->toDateString(), 'total' => $doc->total] : null,
        ];
    }

    /** Mirrors RecurringInvoiceService::calculateNextBillDate (first anchor+k*cycle >= today). */
    public function nextBillDate(ClientSubscription $sub): ?Carbon
    {
        $cycle = $sub->productService?->billing_cycle;
        if (!$cycle || !isset(self::CYCLE_MONTHS[$cycle]) || !$sub->start_date) {
            return null;
        }
        $d = $sub->start_date->copy();
        $today = Carbon::today();
        while ($d->lt($today)) {
            $d->addMonths(self::CYCLE_MONTHS[$cycle]);
        }

        return $d;
    }

    /**
     * Called by ClientSubscriptionObserver for linode-type subscriptions. Deliberately makes NO Linode API
     * call and touches nothing else: it only leaves an audit/log trail so staff act manually if needed.
     */
    public function noteStatusChange(ClientSubscription $sub): void
    {
        $r = LinodeResource::withoutGlobalScopes()->where('tenant_id', $sub->tenant_id)->where('client_subscription_id', $sub->id)->first();
        Log::warning('Linode subscription status changed - billing only, the Linode server was NOT touched', [
            'subscription_id' => $sub->id, 'status' => $sub->status, 'linode_resource_id' => $r?->id,
        ]);
        if ($r) {
            LinodeAuditLog::withoutGlobalScopes()->create([
                'tenant_id' => $sub->tenant_id, 'user_id' => auth()->id(), 'linode_account_id' => $r->linode_account_id,
                'action' => 'subscription.status_changed', 'target' => $r->label,
                'request' => ['client_subscription_id' => $sub->id, 'status' => $sub->status, 'note' => 'Billing state only; no action taken at Linode - handle the server manually if required.'],
                'response_status' => 200,
            ]);
        }
    }

    private function assertNotBilled(LinodeResource $r): void
    {
        if ($r->client_subscription_id && ClientSubscription::where('id', $r->client_subscription_id)->whereIn('status', self::LIVE)->exists()) {
            throw new \DomainException('This server already has an active subscription. Unlink it first if you really want to bill it again.');
        }
    }

    private function audit(LinodeResource $r, string $action, array $extra): void
    {
        LinodeAuditLog::create([
            'tenant_id' => $r->tenant_id, 'user_id' => auth()->id(), 'linode_account_id' => $r->linode_account_id,
            'action' => $action, 'target' => $r->label, 'request' => $extra, 'response_status' => 200,
        ]);
    }
}
