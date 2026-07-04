<?php

namespace App\Services\WhmcsImport;

use App\Models\Client;
use App\Models\ClientSubscription;
use App\Models\ClientUser;
use App\Models\Document;
use App\Models\DocumentItem;
use App\Models\PaymentIn;
use App\Models\ProductService;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * One-time WHMCS -> MoBilling importer (docs/IMPLEMENTATION_PLAN.md §C1).
 *
 * Reads the `whmcs` connection (raw WHMCS schema), writes MoBilling models on the
 * default connection. Idempotent: every row is keyed on (tenant_id, legacy_id) so
 * re-runs update instead of duplicating. All monetary values are TZS (verified:
 * single-currency install). Stage order matters: products -> clients -> users ->
 * services -> invoices -> payments.
 */
class WhmcsImporter
{
    /** stage report: [stage => ['imported' => n, 'skipped' => [[reason, ref], ...]]] */
    public array $report = [];

    private const CYCLE_MAP = [
        'Monthly'       => 'monthly',
        'Quarterly'     => 'quarterly',
        'Semi-Annually' => 'half_yearly',
        'Annually'      => 'yearly',
        'One Time'      => 'once',
        'Free Account'  => 'once',
    ];

    private const SERVICE_STATUS_MAP = [
        'Pending'    => 'pending',
        'Active'     => 'active',
        'Suspended'  => 'suspended',
        'Terminated' => 'cancelled',
        'Cancelled'  => 'cancelled',
        'Fraud'      => 'cancelled',
        'Completed'  => 'cancelled',
    ];

    public function __construct(private string $tenantId, private ?int $limit = null) {}

    private function whmcs(string $table)
    {
        $q = DB::connection('whmcs')->table($table);
        if ($this->limit) $q->limit($this->limit);
        return $q;
    }

    private function ok(string $stage): void
    {
        $this->report[$stage]['imported'] = ($this->report[$stage]['imported'] ?? 0) + 1;
    }

    private function skip(string $stage, string $reason, string $ref): void
    {
        $this->report[$stage]['skipped'][] = [$reason, $ref];
    }

    private function date(?string $d): ?string
    {
        return ($d && $d !== '0000-00-00' && !str_starts_with($d, '0000')) ? $d : null;
    }

    // ── Stage: products ────────────────────────────────────────────────────────

    public function importProducts(): void
    {
        $pricing = DB::connection('whmcs')->table('tblpricing')
            ->where('type', 'product')->where('currency', 1)
            ->get()->keyBy('relid');

        foreach ($this->whmcs('tblproducts')->orderBy('id')->get() as $p) {
            [$cycle, $price] = $this->resolveProductPricing($p, $pricing->get($p->id));

            ProductService::withoutGlobalScopes()->updateOrCreate(
                ['tenant_id' => $this->tenantId, 'legacy_id' => $p->id],
                [
                    'type'          => 'service',
                    'name'          => trim($p->name) ?: "WHMCS product {$p->id}",
                    'code'          => "WHMCS-P{$p->id}",
                    'description'   => trim(strip_tags($p->description ?? '')) ?: null,
                    'price'         => $price,
                    'tax_percent'   => 0,
                    'unit'          => null,
                    'category'      => $p->servertype ?: 'whmcs',
                    'billing_cycle' => $cycle,
                    'is_active'     => !($p->hidden ?? 0),
                ]
            );
            $this->ok('products');
        }
    }

    /** Pick the first enabled cycle from tblpricing (-1 = disabled). One-time uses the monthly column. */
    private function resolveProductPricing(object $p, ?object $pr): array
    {
        if (($p->paytype ?? 'recurring') === 'free') return ['once', 0];

        if (($p->paytype ?? '') === 'onetime') {
            return ['once', max((float) ($pr->monthly ?? 0), 0)];
        }

        foreach (['annually' => 'yearly', 'monthly' => 'monthly', 'quarterly' => 'quarterly', 'semiannually' => 'half_yearly'] as $col => $cycle) {
            if ($pr && (float) $pr->$col >= 0) return [$cycle, (float) $pr->$col];
        }

        return ['yearly', 0]; // no pricing row — placeholder, flagged by price 0
    }

    // ── Stage: clients ─────────────────────────────────────────────────────────

    public function importClients(): void
    {
        // Existing MoBilling clients — many WHMCS customers already exist here
        // (the tenant ran both systems in parallel). Match by email or normalized
        // phone and ADOPT the existing client instead of creating a duplicate.
        $existing = Client::withoutGlobalScopes()->withTrashed()
            ->where('tenant_id', $this->tenantId)
            ->get(['id', 'email', 'phone', 'address', 'tax_id', 'notes', 'legacy_id']);

        $byEmail = $existing->whereNotNull('email')->keyBy(fn ($x) => mb_strtolower($x->email));
        $byPhone = $existing->whereNotNull('phone')->keyBy(fn ($x) => preg_replace('/\D/', '', $x->phone));

        $seenEmails = $byEmail->keys()->flip()->all();
        $seenPhones = Client::withoutGlobalScopes()->withTrashed()
            ->where('tenant_id', $this->tenantId)->whereNotNull('phone')->pluck('phone')->flip()->all();

        foreach ($this->whmcs('tblclients')->orderBy('id')->get() as $c) {
            $name = trim($c->companyname) ?: trim("{$c->firstname} {$c->lastname}");
            if ($name === '') {
                $this->skip('clients', 'no name', "tblclients.id={$c->id}");
                continue;
            }

            $email      = mb_strtolower(trim($c->email)) ?: null;
            $phone      = trim($c->phonenumber) ?: null;
            $phoneDigits = $phone ? preg_replace('/\D/', '', $phone) : null;
            $address = implode(', ', array_filter(array_map('trim', [
                $c->address1, $c->address2, $c->city, $c->state, $c->postcode, $c->country,
            ]))) ?: null;

            // Re-run idempotency: already imported/adopted?
            $target = $existing->firstWhere('legacy_id', $c->id)
                ?? ($email ? $byEmail->get($email) : null)
                ?? ($phoneDigits ? $byPhone->get($phoneDigits) : null);

            if ($target) {
                if ($target->legacy_id && $target->legacy_id !== $c->id) {
                    // Existing client already adopted by another WHMCS client
                    // (WHMCS allows duplicate emails) — import this one separately below.
                    $target = null;
                } else {
                    // Merge: keep the MoBilling identity (name/email/phone), fill blanks only.
                    Client::withoutGlobalScopes()->withTrashed()->where('id', $target->id)->update(array_filter([
                        'legacy_id' => $c->id,
                        'address'   => $target->address ?: $address,
                        'tax_id'    => $target->tax_id ?: (trim($c->tax_id) ?: null),
                        'notes'     => $target->notes ?: (trim($c->notes) ?: null),
                    ], fn ($v) => !is_null($v)));
                    $target->legacy_id = $c->id;
                    $this->ok('clients (merged with existing)');
                    continue;
                }
            }

            // New client — respect per-tenant unique (email)/(phone) by blanking collisions.
            if ($email && isset($seenEmails[$email])) {
                $this->skip('clients', 'duplicate email blanked', "tblclients.id={$c->id} {$email}");
                $email = null;
            }
            if ($phone && isset($seenPhones[$phone])) {
                $this->skip('clients', 'duplicate phone blanked', "tblclients.id={$c->id} {$phone}");
                $phone = null;
            }

            $created = Client::withoutGlobalScopes()->withTrashed()->updateOrCreate(
                ['tenant_id' => $this->tenantId, 'legacy_id' => $c->id],
                [
                    'name'    => $name,
                    'email'   => $email,
                    'phone'   => $phone,
                    'address' => $address,
                    'tax_id'  => trim($c->tax_id) ?: null,
                    'status'  => $c->status === 'Active' ? 'active' : 'inactive',
                    'notes'   => trim($c->notes) ?: null,
                ]
            );

            $existing->push($created);
            if ($email) { $seenEmails[$email] = true; $byEmail->put($email, $created); }
            if ($phone) { $seenPhones[$phone] = true; if ($phoneDigits) $byPhone->put($phoneDigits, $created); }
            $this->ok('clients');
        }
    }

    // ── Stage: users (portal logins) ───────────────────────────────────────────

    public function importUsers(): void
    {
        $clientMap = $this->legacyMap(Client::class);

        $pivots = DB::connection('whmcs')->table('tblusers_clients')
            ->join('tblusers', 'tblusers.id', '=', 'tblusers_clients.auth_user_id')
            ->orderByDesc('tblusers_clients.owner')->orderBy('tblusers_clients.id')
            ->select('tblusers.*', 'tblusers_clients.client_id as whmcs_client_id', 'tblusers_clients.owner')
            ->get();

        $seenEmails = ClientUser::withoutGlobalScopes()
            ->where('tenant_id', $this->tenantId)->whereNull('legacy_id')
            ->pluck('email')->map(fn ($e) => mb_strtolower($e))->flip()->all();

        foreach ($pivots as $u) {
            $clientId = $clientMap[$u->whmcs_client_id] ?? null;
            if (!$clientId) {
                $this->skip('users', 'client not imported', "tblusers.id={$u->id}");
                continue;
            }

            $email = mb_strtolower(trim($u->email));
            if ($email === '') {
                $this->skip('users', 'no email', "tblusers.id={$u->id}");
                continue;
            }

            // client_users is unique (email, tenant): a WHMCS login shared across
            // several clients keeps its owner link only; the rest are reported.
            $existing = ClientUser::withoutGlobalScopes()
                ->where('tenant_id', $this->tenantId)->where('email', $email)->first();
            if (($existing && $existing->legacy_id !== $u->id) || (!$existing && isset($seenEmails[$email]))) {
                $this->skip('users', 'email already used (shared login?)', "tblusers.id={$u->id} {$email}");
                continue;
            }

            // WHMCS >= 5.3 hashes are bcrypt ($2y$) — Laravel-compatible as-is.
            $isBcrypt = str_starts_with($u->password ?? '', '$2y$') || str_starts_with($u->password ?? '', '$2a$');
            if (!$isBcrypt) {
                $this->skip('users', 'legacy hash - imported with random password', "tblusers.id={$u->id} {$email}");
            }

            ClientUser::withoutGlobalScopes()->updateOrCreate(
                ['tenant_id' => $this->tenantId, 'legacy_id' => $u->id],
                [
                    'client_id'     => $clientId,
                    'name'          => trim("{$u->first_name} {$u->last_name}") ?: $email,
                    'email'         => $email,
                    // forceFill-style raw hash: model casts password as 'hashed',
                    // which leaves already-hashed values intact.
                    'password'      => $isBcrypt ? $u->password : Str::random(40),
                    'role'          => $u->owner ? 'admin' : 'viewer',
                    'is_active'     => true,
                    'last_login_at' => $this->date($u->last_login ? substr($u->last_login, 0, 10) : null) ? $u->last_login : null,
                ]
            );

            $seenEmails[$email] = true;
            $this->ok('users');
        }
    }

    // ── Stage: services ────────────────────────────────────────────────────────

    public function importServices(): void
    {
        $clientMap  = $this->legacyMap(Client::class);
        $productMap = $this->legacyMap(ProductService::class);
        $catalog    = ProductService::withoutGlobalScopes()
            ->where('tenant_id', $this->tenantId)->whereNotNull('legacy_id')
            ->get()->keyBy('legacy_id');

        foreach ($this->whmcs('tblhosting')->orderBy('id')->get() as $h) {
            $clientId = $clientMap[$h->userid] ?? null;
            if (!$clientId) {
                $this->skip('services', 'client not imported', "tblhosting.id={$h->id}");
                continue;
            }

            $cycle = self::CYCLE_MAP[$h->billingcycle] ?? 'yearly';
            $qty   = max((int) $h->qty, 1);
            $price = round(((float) $h->amount) / $qty, 2);

            $productId = $this->resolveServiceProduct($h, $cycle, $price, $catalog, $productMap);

            $regdate  = $this->date($h->regdate);
            $nextDue  = $this->date($h->nextduedate);

            // Billing anchor: RecurringInvoiceService walks start_date forward by
            // whole cycles, so anchor start_date one cycle before nextduedate to make
            // the walk land exactly on the WHMCS renewal date. The true registration
            // date is preserved in metadata.
            $startDate = $regdate;
            if ($cycle !== 'once' && $nextDue) {
                $startDate = $this->minusOneCycle(Carbon::parse($nextDue), $cycle)->toDateString();
            }

            ClientSubscription::withoutGlobalScopes()->withTrashed()->updateOrCreate(
                ['tenant_id' => $this->tenantId, 'legacy_id' => $h->id],
                [
                    'client_id'          => $clientId,
                    'product_service_id' => $productId,
                    'label'              => trim($h->domain) ?: null,
                    'quantity'           => $qty,
                    'start_date'         => $startDate ?? $regdate ?? now()->toDateString(),
                    'expire_date'        => $nextDue,
                    'status'             => self::SERVICE_STATUS_MAP[$h->domainstatus] ?? 'cancelled',
                    'metadata'           => [
                        'whmcs_status'   => $h->domainstatus,
                        'whmcs_regdate'  => $regdate,
                        'domain'         => trim($h->domain) ?: null,
                        'cpanel_username'=> trim($h->username) ?: null,
                        'server_id'      => $h->server ?: null,
                        'dedicated_ip'   => trim($h->dedicatedip) ?: null,
                        'suspend_reason' => trim($h->suspendreason) ?: null,
                    ],
                ]
            );
            $this->ok('services');
        }
    }

    /**
     * A WHMCS service may have an admin-overridden price/cycle differing from the
     * catalog product. Billing in MoBilling comes from the product, so such services
     * get a price-accurate variant product (idempotent via code).
     */
    private function resolveServiceProduct(object $h, string $cycle, float $price, $catalog, array $productMap): string
    {
        $base = $catalog->get($h->packageid);

        if ($base && (float) $base->price === $price && $base->billing_cycle === $cycle) {
            return $base->id;
        }

        $code    = sprintf('WHMCS-P%d-%s-%s', $h->packageid, $cycle, number_format($price, 0, '', ''));
        $variant = ProductService::withoutGlobalScopes()
            ->where('tenant_id', $this->tenantId)->where('code', $code)->first();

        return $variant?->id ?? ProductService::withoutGlobalScopes()->create([
            'tenant_id'     => $this->tenantId,
            'type'          => 'service',
            'name'          => ($base?->name ?? "WHMCS product {$h->packageid}"),
            'code'          => $code,
            'description'   => $base?->description,
            'price'         => $price,
            'tax_percent'   => 0,
            'category'      => $base?->category ?? 'whmcs',
            'billing_cycle' => $cycle,
            'is_active'     => true,
        ])->id;
    }

    private function minusOneCycle(Carbon $d, string $cycle): Carbon
    {
        return match ($cycle) {
            'monthly'     => $d->subMonthNoOverflow(),
            'quarterly'   => $d->subMonthsNoOverflow(3),
            'half_yearly' => $d->subMonthsNoOverflow(6),
            default       => $d->subYearNoOverflow(),
        };
    }

    // ── Stage: invoices ────────────────────────────────────────────────────────

    public function importInvoices(): void
    {
        $clientMap = $this->legacyMap(Client::class);

        $itemsByInvoice = DB::connection('whmcs')->table('tblinvoiceitems')
            ->where('invoiceid', '>', 0)->get()->groupBy('invoiceid');

        foreach ($this->whmcs('tblinvoices')->orderBy('id')->get() as $inv) {
            $clientId = $clientMap[$inv->userid] ?? null;
            if (!$clientId) {
                $this->skip('invoices', 'client not imported', "tblinvoices.id={$inv->id}");
                continue;
            }

            $items    = $itemsByInvoice->get($inv->id, collect());
            $isTopUp  = $items->contains(fn ($i) => $i->type === 'AddFunds');
            // Number by the unique WHMCS id — invoicenum is optional and can collide
            // with another invoice's id. The custom number is preserved in notes.
            $number   = 'WHMCS-' . $inv->id;

            $doc = Document::withoutGlobalScopes()->withTrashed()->updateOrCreate(
                ['tenant_id' => $this->tenantId, 'legacy_id' => $inv->id],
                [
                    'client_id'       => $clientId,
                    'type'            => 'invoice',
                    'document_number' => $number,
                    'date'            => $this->date($inv->date) ?? $this->date($inv->duedate) ?? now()->toDateString(),
                    'due_date'        => $this->date($inv->duedate),
                    'subtotal'        => (float) $inv->subtotal,
                    'discount_amount' => 0,
                    'tax_amount'      => (float) $inv->tax + (float) $inv->tax2,
                    'total'           => (float) $inv->total,
                    'status'          => $this->invoiceStatus($inv),
                    'notes'           => trim(implode(' ', array_filter([
                        $inv->notes,
                        $inv->invoicenum ? "[WHMCS number: {$inv->invoicenum}]" : null,
                        $isTopUp ? '[WHMCS AddFunds top-up]' : null,
                        $inv->status === 'Refunded' ? '[WHMCS: Refunded]' : null,
                    ]))) ?: null,
                ]
            );

            // Rebuild line items idempotently (delete + insert is safe: legacy docs only).
            DocumentItem::where('document_id', $doc->id)->delete();
            foreach ($items as $it) {
                DocumentItem::create([
                    'document_id' => $doc->id,
                    'item_type'   => 'service',
                    // document_items.description is varchar(255); WHMCS lines can be long
                    'description' => Str::limit(trim(preg_replace('/\s+/', ' ', $it->description)) ?: $it->type, 250),
                    'quantity'    => 1,
                    'price'       => (float) $it->amount,
                    'tax_percent' => 0,
                    'tax_amount'  => 0,
                    'total'       => (float) $it->amount,
                ]);
            }

            $this->ok('invoices');
        }
    }

    private function invoiceStatus(object $inv): string
    {
        return match ($inv->status) {
            'Paid'            => 'paid',
            'Cancelled',
            'Refunded'        => 'cancelled',
            'Draft'           => 'draft',
            'Collections'     => 'overdue',
            'Payment Pending' => 'sent',
            default           => ($this->date($inv->duedate) && Carbon::parse($inv->duedate)->isPast())
                                    ? 'overdue' : 'sent', // Unpaid
        };
    }

    // ── Stage: payments ────────────────────────────────────────────────────────

    public function importPayments(): void
    {
        $clientMap   = $this->legacyMap(Client::class);
        $documentMap = $this->legacyMap(Document::class);

        foreach ($this->whmcs('tblaccounts')->orderBy('id')->get() as $t) {
            if ((float) $t->amountout > 0) {
                $this->skip('payments', 'refund/debit (no refund model)', "tblaccounts.id={$t->id} out={$t->amountout}");
                continue;
            }
            if ((float) $t->amountin <= 0) {
                $this->skip('payments', 'zero amount', "tblaccounts.id={$t->id}");
                continue;
            }

            $clientId = $clientMap[$t->userid] ?? null;
            if (!$clientId) {
                $this->skip('payments', 'client not imported', "tblaccounts.id={$t->id}");
                continue;
            }

            PaymentIn::withoutGlobalScopes()->updateOrCreate(
                ['tenant_id' => $this->tenantId, 'legacy_id' => $t->id],
                [
                    'client_id'      => $clientId,
                    'document_id'    => $documentMap[$t->invoiceid] ?? null,
                    'amount'         => (float) $t->amountin,
                    'payment_date'   => substr($t->date, 0, 10),
                    'payment_method' => $t->gateway ?: 'other',
                    'reference'      => trim($t->transid) ?: null,
                    'notes'          => trim($t->description) ?: null,
                ]
            );
            $this->ok('payments');
        }

        $this->synthesizeCreditPayments($clientMap, $documentMap);
    }

    /**
     * WHMCS invoices paid (partly) by account credit have no tblaccounts row for the
     * credit portion — synthesize a payment so MoBilling's balance_due reaches zero.
     */
    private function synthesizeCreditPayments(array $clientMap, array $documentMap): void
    {
        $creditInvoices = DB::connection('whmcs')->table('tblinvoices')
            ->where('credit', '>', 0)->whereIn('status', ['Paid'])->get();

        foreach ($creditInvoices as $inv) {
            $docId    = $documentMap[$inv->id] ?? null;
            $clientId = $clientMap[$inv->userid] ?? null;
            if (!$docId || !$clientId) continue;

            $exists = PaymentIn::withoutGlobalScopes()
                ->where('tenant_id', $this->tenantId)
                ->where('document_id', $docId)
                ->where('payment_method', 'credit')
                ->exists();
            if ($exists) continue;

            PaymentIn::withoutGlobalScopes()->create([
                'tenant_id'      => $this->tenantId,
                'client_id'      => $clientId,
                'document_id'    => $docId,
                'amount'         => (float) $inv->credit,
                'payment_date'   => $this->date($inv->datepaid ? substr($inv->datepaid, 0, 10) : null)
                                        ?? $this->date($inv->date) ?? now()->toDateString(),
                'payment_method' => 'credit',
                'notes'          => 'WHMCS account credit applied',
            ]);
            $this->ok('payments (credit synth)');
        }
    }

    // ── Stage: domains ─────────────────────────────────────────────────────────

    private const DOMAIN_STATUS_MAP = [
        'Pending'              => 'pending',
        'Pending Registration' => 'pending',
        'Pending Transfer'     => 'pending',
        'Active'               => 'active',
        'Expired'              => 'expired',
        'Cancelled'            => 'cancelled',
        'Fraud'                => 'cancelled',
        'Transferred Away'     => 'transferred_out',
    ];

    public function importDomains(): void
    {
        $clientMap = $this->legacyMap(\App\Models\Client::class);

        $platformAccount = \App\Models\RegistrarAccount::whereNull('tenant_id')
            ->where('is_active', true)->first();

        // WHMCS keeps re-registration history rows for the same name; our table has a
        // global unique(name). Keep the best row per name: Active > Pending > Expired
        // > Cancelled, tie-break latest id.
        $rank = ['Active' => 0, 'Pending' => 1, 'Pending Registration' => 1, 'Pending Transfer' => 1, 'Expired' => 2];
        $rows = DB::connection('whmcs')->table('tbldomains')->orderBy('id')->get()
            ->groupBy(fn ($d) => strtolower(trim($d->domain)))
            ->map(function ($group) use ($rank) {
                $best = $group->sortBy([
                    fn ($a, $b) => ($rank[$a->status] ?? 3) <=> ($rank[$b->status] ?? 3),
                    fn ($a, $b) => $b->id <=> $a->id,
                ])->first();
                foreach ($group as $g) {
                    if ($g->id !== $best->id) {
                        $this->skip('domains', 'duplicate name - kept best row', "tbldomains.id={$g->id} {$g->domain} (kept {$best->id})");
                    }
                }
                return $best;
            });

        foreach ($rows as $d) {
            $clientId = $clientMap[$d->userid] ?? null;
            if (!$clientId) {
                $this->skip('domains', 'client not imported', "tbldomains.id={$d->id} {$d->domain}");
                continue;
            }

            $domain = \App\Models\Domain::withoutGlobalScopes()->firstOrNew(
                ['tenant_id' => $this->tenantId, 'legacy_id' => $d->id],
            );
            $domain->fill([
                'client_id'            => $clientId,
                'registrar_account_id' => $platformAccount?->id,
                'name'                 => strtolower(trim($d->domain)),
                'status'               => self::DOMAIN_STATUS_MAP[$d->status] ?? 'cancelled',
                'registered_at'        => $this->date($d->registrationdate),
                'expires_at'           => $this->date($d->expirydate),
                // merge — never wipe sync-owned keys (sponsoring_registrar, ssl_*, …)
                'meta'                 => array_merge($domain->meta ?? [], [
                    'whmcs_status'        => $d->status,
                    'whmcs_registrar'     => $d->registrar ?: null,
                    'whmcs_nextduedate'   => $this->date($d->nextduedate),
                    'whmcs_recurring_amt' => (float) $d->recurringamount,
                ]),
            ]);
            if (!$domain->exists) {
                // policy: auto-renew starts OFF; the client opts in via the portal
                $domain->auto_renew = false;
            }
            $domain->save();
            $this->ok('domains');
        }
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    /** [whmcs_id => uuid] for already-imported rows of a model. */
    private function legacyMap(string $model): array
    {
        $q = $model::withoutGlobalScopes();
        if (in_array(\Illuminate\Database\Eloquent\SoftDeletes::class, class_uses_recursive($model))) {
            $q->withTrashed();
        }
        return $q->where('tenant_id', $this->tenantId)
            ->whereNotNull('legacy_id')
            ->pluck('id', 'legacy_id')
            ->all();
    }
}
