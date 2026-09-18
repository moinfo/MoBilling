<?php

namespace App\Http\Controllers\Portal;

use App\Exceptions\WhmApiException;
use App\Http\Controllers\Controller;
use App\Models\HostingAccount;
use App\Models\HostingAccountBackupSetting;
use App\Services\WhmService;
use Illuminate\Http\Request;

class PortalHostingController extends Controller
{
    /** The authed client's hosting accounts (safe fields only). */
    public function index(Request $request)
    {
        $clientId = $request->user()->client_id;
        $tenantId = $request->user()->tenant_id;

        $accounts = HostingAccount::with(['server:id,name,hostname', 'subscription:id,client_id,label,expire_date'])
            ->whereHas('subscription', fn ($q) => $q->where('client_id', $clientId))
            ->whereNotIn('status', ['terminated'])
            ->orderBy('domain')
            ->get();

        // Backup add-on subscriptions are matched by domain name (label),
        // same convention as hosting:backup-paid-accounts and
        // hasActiveBackupSubscription() — not linked via client_subscription_id.
        $domains = $accounts->pluck('domain')->filter()->values()->all();
        $backupSubs = \App\Models\ClientSubscription::withoutGlobalScopes()
            ->whereNull('deleted_at')
            ->where('tenant_id', $tenantId)->where('client_id', $clientId)
            ->whereIn('label', $domains)
            ->whereIn('status', ['active', 'pending'])
            ->whereHas('productService', fn ($q) => $q->where('category', 'Backup'))
            ->get()
            ->keyBy('label');

        // Ascending, so keyBy() below keeps the NEWEST log per subscription
        // (later items in the collection overwrite earlier ones).
        $pendingLogsBySubscription = \App\Models\RecurringInvoiceLog::withoutGlobalScopes()
            ->whereIn('client_subscription_id', $backupSubs->where('status', 'pending')->pluck('id'))
            ->orderBy('invoice_created_at')
            ->get()
            ->keyBy('client_subscription_id');

        $accounts = $accounts->map(function ($a) use ($backupSubs, $pendingLogsBySubscription) {
            $backupSub = $backupSubs->get($a->domain);
            $pendingLog = $backupSub?->status === 'pending' ? $pendingLogsBySubscription->get($backupSub->id) : null;

            return [
                'id'                       => $a->id,
                'domain'                   => $a->domain,
                'cpanel_username'          => $a->cpanel_username,
                'package'                  => $a->meta['plan'] ?? $a->package,
                'status'                   => $a->status,
                'disk_used'                => $a->meta['disk_used'] ?? null,
                'disk_limit'               => $a->meta['disk_limit'] ?? null,
                'server_hostname'          => $a->server?->hostname,
                'expires_at'               => $a->subscription?->expire_date?->toDateString(),
                'backup_status'            => $backupSub?->status ?? 'none',
                'backup_pending_document'  => $pendingLog?->document_id,
            ];
        });

        return response()->json(['data' => $accounts]);
    }

    /** cPanel tool deep-links offered as Quick Shortcuts (whitelist). */
    private const GOTO_MAP = [
        'email'      => '/frontend/jupiter/email_accounts/index.html',
        'forwarders' => '/frontend/jupiter/mail/fwds.html',
        'files'      => '/frontend/jupiter/filemanager/index.html',
        'backup'     => '/frontend/jupiter/backup/index.html',
        'domains'    => '/frontend/jupiter/domains/index.html',
        'cron'       => '/frontend/jupiter/cron/index.html',
        'mysql'      => '/frontend/jupiter/sql/index.html',
        'phpmyadmin' => '/3rdparty/phpMyAdmin/index.php',
        'stats'      => '/frontend/jupiter/stats/awstats.html',
    ];

    private function guardAccount(Request $request, HostingAccount $hostingAccount, bool $adminOnly = true): void
    {
        $user = $request->user();
        abort_unless($hostingAccount->subscription?->client_id === $user->client_id, 404);
        if ($adminOnly) {
            abort_unless($user->role === 'admin', 403, 'Only portal administrators can do this.');
        }
    }

    /** Full detail for the Service Details page. */
    public function show(Request $request, HostingAccount $hostingAccount)
    {
        $this->guardAccount($request, $hostingAccount, adminOnly: false);

        $sub = $hostingAccount->subscription?->load('productService');
        $p   = $sub?->productService;

        return response()->json(['data' => [
            'id'              => $hostingAccount->id,
            'domain'          => $hostingAccount->domain,
            'cpanel_username' => $hostingAccount->cpanel_username,
            'status'          => $hostingAccount->status,
            'package'         => $hostingAccount->meta['plan'] ?? $hostingAccount->package,
            'product_name'    => $p?->name,
            'product_group'   => $p?->category,
            'price'           => (float) ($p?->price ?? 0),
            'billing_cycle'   => $p?->billing_cycle,
            'registered_at'   => $sub?->start_date?->toDateString(),
            'next_due'        => $sub?->expire_date?->toDateString(),
            'disk_used'       => $hostingAccount->meta['disk_used'] ?? null,
            'disk_limit'      => $hostingAccount->meta['disk_limit'] ?? null,
            'bw_used_bytes'   => $hostingAccount->meta['bw_used_bytes'] ?? null,
            'bw_limit_bytes'  => $hostingAccount->meta['bw_limit_bytes'] ?? null,
            'last_synced_at'  => $hostingAccount->last_synced_at?->toISOString(),
            'shortcuts'       => array_keys(self::GOTO_MAP),
        ]]);
    }

    /**
     * Live usage refresh — disk via accountsummary, bandwidth via showbw.
     * accountsummary was confirmed (elsewhere this session) to never
     * actually carry bandwidth fields despite the field names suggesting it
     * might — showbw is the only WHM call that does, and it's server-wide
     * (no per-account variant exists), so this pulls the whole server's
     * figures and picks out this one account's row.
     */
    public function refreshUsage(Request $request, HostingAccount $hostingAccount)
    {
        $this->guardAccount($request, $hostingAccount, adminOnly: false);

        try {
            $whm = (new WhmService($hostingAccount->server))->forAccount($hostingAccount->id);
            $summary = $whm->accountSummary($hostingAccount->cpanel_username);

            $bwRow = collect($whm->bandwidthUsage())
                ->first(fn ($a) => strcasecmp((string) ($a['user'] ?? ''), $hostingAccount->cpanel_username) === 0);
            $bwLimitBytes = (int) ($bwRow['limit'] ?? 0); // 0 = unlimited, WHM's own convention

            $hostingAccount->update([
                'last_synced_at' => now(),
                'meta' => array_merge($hostingAccount->meta ?? [], [
                    'disk_used'         => $summary['diskused'] ?? null,
                    'disk_limit'        => $summary['disklimit'] ?? null,
                    'plan'              => $summary['plan'] ?? null,
                    'bw_used_bytes'     => $bwRow ? (int) ($bwRow['totalbytes'] ?? 0) : null,
                    'bw_limit_bytes'    => $bwRow && $bwLimitBytes > 0 ? $bwLimitBytes : null,
                ]),
            ]);

            $fresh = $hostingAccount->fresh();
            return response()->json(['data' => [
                'disk_used'      => $fresh->meta['disk_used'] ?? null,
                'disk_limit'     => $fresh->meta['disk_limit'] ?? null,
                'bw_used_bytes'  => $fresh->meta['bw_used_bytes'] ?? null,
                'bw_limit_bytes' => $fresh->meta['bw_limit_bytes'] ?? null,
                'last_synced_at' => now()->toISOString(),
            ]]);
        } catch (WhmApiException) {
            return response()->json(['message' => 'Could not reach the hosting server — try again later.'], 422);
        }
    }

    /**
     * This account's own subdomains and addon domains — WHM's
     * get_domain_info is server-wide (same call the staff Subdomains page
     * uses), filtered here to just this one cPanel account's rows.
     */
    public function subdomains(Request $request, HostingAccount $hostingAccount)
    {
        $this->guardAccount($request, $hostingAccount, adminOnly: false);

        try {
            $domains = (new WhmService($hostingAccount->server))
                ->forAccount($hostingAccount->id)
                ->listDomains();
        } catch (WhmApiException) {
            return response()->json(['message' => 'Could not reach the hosting server — try again later.'], 422);
        }

        $rows = collect($domains)
            ->filter(fn ($d) => in_array($d['domain_type'] ?? null, ['sub', 'addon'], true)
                && strcasecmp((string) ($d['user'] ?? ''), $hostingAccount->cpanel_username) === 0)
            ->map(fn ($d) => [
                'type'          => $d['domain_type'],
                'domain'        => $d['domain'] ?? null,
                'parent_domain' => $d['parent_domain'] ?? null,
            ])
            ->values();

        return response()->json(['data' => $rows]);
    }

    /** This account's mailboxes — same WhmService::emailAccounts() the staff page uses. */
    public function emailAccounts(Request $request, HostingAccount $hostingAccount)
    {
        $this->guardAccount($request, $hostingAccount, adminOnly: false);

        try {
            $pops = (new WhmService($hostingAccount->server))
                ->forAccount($hostingAccount->id)
                ->emailAccounts($hostingAccount->cpanel_username);
        } catch (WhmApiException) {
            return response()->json(['message' => 'Could not reach the hosting server — try again later.'], 422);
        }

        // list_pops_with_disk's quota is 0 (int) when unlimited, a numeric
        // byte-count string otherwise — matches the staff endpoint's mapping.
        $rows = array_map(function ($p) {
            $quotaBytes = (int) ($p['_diskquota'] ?? 0);
            return [
                'email'              => $p['email'] ?? null,
                'suspended_incoming' => (bool) ($p['suspended_incoming'] ?? false),
                'suspended_login'    => (bool) ($p['suspended_login'] ?? false),
                'used_bytes'         => (int) ($p['_diskused'] ?? 0),
                'quota_bytes'        => $quotaBytes > 0 ? $quotaBytes : null,
            ];
        }, $pops);

        return response()->json(['data' => $rows]);
    }

    /** This account's MySQL databases — same WhmService::mysqlDatabases() the staff page uses. */
    public function mysqlDatabases(Request $request, HostingAccount $hostingAccount)
    {
        $this->guardAccount($request, $hostingAccount, adminOnly: false);

        try {
            $dbs = (new WhmService($hostingAccount->server))
                ->forAccount($hostingAccount->id)
                ->mysqlDatabases($hostingAccount->cpanel_username);
        } catch (WhmApiException) {
            return response()->json(['message' => 'Could not reach the hosting server — try again later.'], 422);
        }

        $rows = array_map(fn ($d) => [
            'database'   => $d['database'] ?? null,
            'users'      => (array) ($d['users'] ?? []),
            'disk_usage' => (int) ($d['disk_usage'] ?? 0),
        ], $dbs);

        return response()->json(['data' => $rows]);
    }

    /** This account's domains/subdomains with their current PHP version, plus what's installed on the server. */
    public function phpVersions(Request $request, HostingAccount $hostingAccount)
    {
        $this->guardAccount($request, $hostingAccount, adminOnly: false);

        $whm = (new WhmService($hostingAccount->server))->forAccount($hostingAccount->id);

        try {
            $vhosts = $whm->phpVersions($hostingAccount->cpanel_username);
            $installed = $whm->installedPhpVersions($hostingAccount->cpanel_username);
        } catch (WhmApiException) {
            return response()->json(['message' => 'Could not reach the hosting server — try again later.'], 422);
        }

        $rows = array_map(fn ($v) => [
            'vhost'       => $v['vhost'] ?? null,
            'version'     => $v['version'] ?? null,
            'main_domain' => (bool) ($v['main_domain'] ?? false),
        ], $vhosts);

        return response()->json(['data' => $rows, 'installed' => $installed]);
    }

    /** Changing PHP version can break an incompatible site, so this stays admin-only like change-password/cancellation. */
    public function updatePhpVersion(Request $request, HostingAccount $hostingAccount)
    {
        $this->guardAccount($request, $hostingAccount);

        $data = $request->validate([
            'vhost'   => 'required|string|max:255',
            'version' => 'required|string|max:32',
        ]);

        try {
            (new WhmService($hostingAccount->server))
                ->forAccount($hostingAccount->id)
                ->setPhpVersion($hostingAccount->cpanel_username, $data['vhost'], $data['version']);
        } catch (WhmApiException $e) {
            return response()->json(['message' => 'Server rejected the change: ' . $e->getMessage()], 422);
        }

        return response()->json(['message' => 'PHP version updated.']);
    }

    /**
     * The account's actual backup files (same tarballs the "Backup" quick
     * shortcut's cPanel wizard shows/downloads — WhmService::homeDirBackupFiles).
     */
    public function backups(Request $request, HostingAccount $hostingAccount)
    {
        $this->guardAccount($request, $hostingAccount, adminOnly: false);

        try {
            $files = (new WhmService($hostingAccount->server))
                ->forAccount($hostingAccount->id)
                ->homeDirBackupFiles($hostingAccount->cpanel_username);
        } catch (WhmApiException) {
            return response()->json(['message' => 'Could not reach the hosting server — try again later.'], 422);
        }

        $rows = array_map(fn ($f) => [
            'date'  => \Carbon\Carbon::createFromTimestamp($f['mtime'])->toIso8601String(),
            'bytes' => $f['bytes'],
        ], array_reverse($files));

        return response()->json(['data' => $rows]);
    }

    /**
     * Whether this account has an active "Backup" subscription, matching
     * hosting:backup-paid-accounts's own eligibility check (subscription's
     * `label` is the domain name — not linked via client_subscription_id).
     */
    private function hasActiveBackupSubscription(HostingAccount $hostingAccount): bool
    {
        return \App\Models\ClientSubscription::withoutGlobalScopes()
            ->whereNull('deleted_at')
            ->where('tenant_id', $hostingAccount->tenant_id)
            ->where('label', $hostingAccount->domain)
            ->where('status', 'active')
            ->whereHas('productService', fn ($q) => $q->where('category', 'Backup'))
            ->exists();
    }

    /**
     * Self-service: subscribe this hosting account to the "Backup" add-on
     * and create its invoice — pay it any way (Pesapal, bank transfer, or
     * wallet credit) and hosting:backup-paid-accounts picks it up the next
     * time it runs (SubscriptionActivationService, already wired into
     * every payment path, flips the subscription to active the moment the
     * invoice is paid). Mirrors PortalResellerController::subscribe()'s
     * exact idempotency pattern: a lock per (client, domain) plus reusing
     * an already-pending invoice, so a double-click or slow retry can't
     * spawn two subscriptions for the same domain.
     */
    public function subscribeBackup(Request $request, HostingAccount $hostingAccount)
    {
        $this->guardAccount($request, $hostingAccount);
        $tenantId = $hostingAccount->tenant_id;
        $clientId = $hostingAccount->subscription->client_id;

        if ($this->hasActiveBackupSubscription($hostingAccount)) {
            return response()->json(['message' => 'This account already has an active Backup subscription.'], 422);
        }

        $product = \App\Models\ProductService::withoutGlobalScopes()
            ->whereNull('deleted_at')
            ->where('tenant_id', $tenantId)->where('category', 'Backup')->where('is_active', true)
            ->first();
        if (!$product) {
            return response()->json(['message' => 'Backup is not available right now — please contact us.'], 422);
        }

        $lock = \Illuminate\Support\Facades\Cache::lock("backup-subscribe:{$clientId}:{$hostingAccount->domain}", 10);

        try {
            return $lock->block(5, function () use ($hostingAccount, $product, $tenantId, $clientId) {
                $pendingSubscription = \App\Models\ClientSubscription::withoutGlobalScopes()
                    ->whereNull('deleted_at')
                    ->where('tenant_id', $tenantId)->where('client_id', $clientId)
                    ->where('product_service_id', $product->id)->where('label', $hostingAccount->domain)
                    ->where('status', 'pending')
                    ->latest('created_at')->first();

                if ($pendingSubscription) {
                    $pendingLog = \App\Models\RecurringInvoiceLog::withoutGlobalScopes()
                        ->where('client_subscription_id', $pendingSubscription->id)
                        ->latest('invoice_created_at')->first();
                    $document = $pendingLog
                        ? \App\Models\Document::withoutGlobalScopes()->whereIn('status', ['sent', 'partial', 'overdue'])->find($pendingLog->document_id)
                        : null;
                    if ($document) {
                        return response()->json([
                            'data'    => ['document_id' => $document->id, 'document_number' => $document->document_number, 'total' => (float) $document->total],
                            'message' => "Invoice {$document->document_number} is awaiting payment — pay it to activate backup for {$hostingAccount->domain}.",
                        ]);
                    }
                }

                $document = \Illuminate\Support\Facades\DB::transaction(function () use ($hostingAccount, $product, $tenantId, $clientId) {
                    $start = now()->startOfDay();

                    $subscription = \App\Models\ClientSubscription::create([
                        'tenant_id'          => $tenantId,
                        'client_id'          => $clientId,
                        'product_service_id' => $product->id,
                        'label'              => $hostingAccount->domain,
                        'quantity'           => 1,
                        'start_date'         => $start,
                        'status'             => 'pending',
                        'recurring_amount'   => $product->price,
                    ]);

                    $document = \App\Models\Document::withoutGlobalScopes()->create([
                        'tenant_id'       => $tenantId,
                        'client_id'       => $clientId,
                        'type'            => 'invoice',
                        'document_number' => app(\App\Services\DocumentNumberService::class)->generate('invoice', $tenantId),
                        'date'            => now()->toDateString(),
                        'due_date'        => now()->addDays(7)->toDateString(),
                        'subtotal'        => $product->price,
                        'discount_amount' => 0,
                        'tax_amount'      => 0,
                        'total'           => $product->price,
                        'status'          => 'sent',
                        'notes'           => "Web Hosting Backup — {$hostingAccount->domain} (self-service, portal)",
                    ]);

                    $document->items()->create([
                        'product_service_id' => $product->id,
                        'item_type'          => 'service',
                        'description'        => "Web Hosting Backup — {$hostingAccount->domain}",
                        'quantity'           => 1,
                        'price'              => $product->price,
                        'tax_percent'        => 0,
                        'tax_amount'         => 0,
                        'total'              => $product->price,
                    ]);

                    \App\Models\RecurringInvoiceLog::withoutGlobalScopes()->create([
                        'tenant_id'              => $tenantId,
                        'client_id'              => $clientId,
                        'product_service_id'     => $product->id,
                        'next_bill_date'         => $start->toDateString(),
                        'client_subscription_id' => $subscription->id,
                        'document_id'            => $document->id,
                        'invoice_created_at'     => now(),
                        'reminders_sent'         => [],
                    ]);

                    return $document;
                });

                return response()->json([
                    'data'    => ['document_id' => $document->id, 'document_number' => $document->document_number, 'total' => (float) $document->total],
                    'message' => "Invoice {$document->document_number} created — pay it any way you like to activate backup for {$hostingAccount->domain}.",
                ], 201);
            });
        } catch (\Illuminate\Contracts\Cache\LockTimeoutException) {
            return response()->json(['message' => 'Still processing your previous request — please wait a moment and try again.'], 429);
        }
    }

    /** This account's backup retention policy — the client's own paid-backup "cron" settings. */
    public function backupSettings(Request $request, HostingAccount $hostingAccount)
    {
        $this->guardAccount($request, $hostingAccount, adminOnly: false);

        $hasBackup = $this->hasActiveBackupSubscription($hostingAccount);
        $settings = $hostingAccount->backupSetting;

        return response()->json([
            'data' => [
                'has_backup'           => $hasBackup,
                'daily_retention_days' => $settings->daily_retention_days ?? HostingAccountBackupSetting::DEFAULT_DAILY_RETENTION_DAYS,
                'keep_weekly'          => $settings->keep_weekly ?? true,
                'keep_monthly'         => $settings->keep_monthly ?? true,
            ],
        ]);
    }

    public function updateBackupSettings(Request $request, HostingAccount $hostingAccount)
    {
        $this->guardAccount($request, $hostingAccount);
        abort_unless($this->hasActiveBackupSubscription($hostingAccount), 422, 'This account does not have an active Backup subscription.');

        $data = $request->validate([
            'daily_retention_days' => 'required|integer|min:1|max:30',
            'keep_weekly'          => 'required|boolean',
            'keep_monthly'         => 'required|boolean',
        ]);

        $settings = HostingAccountBackupSetting::withoutGlobalScopes()->updateOrCreate(
            ['hosting_account_id' => $hostingAccount->id],
            ['tenant_id' => $hostingAccount->tenant_id, ...$data],
        );

        return response()->json([
            'data' => [
                'has_backup'           => true,
                'daily_retention_days' => $settings->daily_retention_days,
                'keep_weekly'          => $settings->keep_weekly,
                'keep_monthly'         => $settings->keep_monthly,
            ],
        ]);
    }

    /** One-time cPanel/Webmail login URL. Portal admins only — SSO grants full hosting control. */
    public function sso(Request $request, HostingAccount $hostingAccount)
    {
        $this->guardAccount($request, $hostingAccount);
        abort_unless($hostingAccount->status === 'active', 422, 'This hosting account is not active.');

        $data = $request->validate([
            'service' => 'nullable|in:cpanel,webmail',
            'goto'    => 'nullable|string|in:' . implode(',', array_keys(self::GOTO_MAP)),
        ]);

        $service = ($data['service'] ?? 'cpanel') === 'webmail' ? 'webmaild' : 'cpaneld';
        $goto    = $service === 'cpaneld' ? (self::GOTO_MAP[$data['goto'] ?? ''] ?? null) : null;

        try {
            $url = (new WhmService($hostingAccount->server))
                ->forAccount($hostingAccount->id)
                ->ssoUrl($hostingAccount->cpanel_username, $service, $goto);

            return response()->json(['url' => $url]);
        } catch (WhmApiException $e) {
            return response()->json(['message' => 'Could not open the control panel right now. Please try again later.'], 422);
        }
    }

    /** Available plans for upgrade/downgrade with the prorated charge for each. */
    public function upgradeOptions(Request $request, HostingAccount $hostingAccount)
    {
        $this->guardAccount($request, $hostingAccount, adminOnly: false);

        $sub = $hostingAccount->subscription?->load('productService');
        abort_unless($sub && $sub->productService, 422, 'Subscription data missing.');

        $svc = app(\App\Services\Hosting\PlanChangeService::class);

        $plans = \App\Models\ProductService::withoutGlobalScopes()
            ->where('tenant_id', $request->user()->tenant_id)
            ->where('is_active', true)
            ->where('portal_visible', true)
            ->where('provisioning_type', 'whm_cpanel')
            ->where('category', $sub->productService->category)
            // exclude WHMCS billing-variant records (same rule as the catalog)
            ->where(fn ($q) => $q->whereNull('code')->orWhere('code', 'not like', 'WHMCS-P%-%'))
            ->orderBy('price')
            ->get()
            ->unique('name')
            ->values()
            ->map(fn ($p) => [
                'id'            => $p->id,
                'name'          => $p->name,
                'price'         => (float) $p->price,
                'billing_cycle' => $p->billing_cycle,
                'is_current'    => $p->id === $sub->product_service_id,
                'due_now'       => $p->id === $sub->product_service_id ? 0.0 : $svc->proratedCharge($sub, $p),
                'credit'        => ($p->id === $sub->product_service_id || !config('whmcs.credit_on_downgrade'))
                    ? 0.0 : $svc->proratedCredit($sub, $p),
            ]);

        return response()->json(['data' => [
            'current_plan' => $sub->productService->name,
            'next_due'     => $sub->expire_date?->toDateString(),
            'plans'        => $plans,
        ]]);
    }

    /** Request the plan change: free/downgrade applies now; upgrade creates a prorated invoice. */
    public function upgrade(Request $request, HostingAccount $hostingAccount)
    {
        $this->guardAccount($request, $hostingAccount);
        abort_unless($hostingAccount->status === 'active', 422, 'This hosting account is not active.');

        $user = $request->user();
        $data = $request->validate([
            'product_service_id' => ['required', 'uuid',
                \Illuminate\Validation\Rule::exists('product_services', 'id')
                    ->where('tenant_id', $user->tenant_id)->where('is_active', true)
                    ->where('provisioning_type', 'whm_cpanel')],
        ]);

        $sub = $hostingAccount->subscription?->load('productService');
        abort_unless($sub, 422, 'Subscription data missing.');
        abort_if(config('whmcs.parallel_mode') && $sub->legacy_id, 422,
            'This service cannot be changed online yet — please contact us.');
        abort_if($sub->product_service_id === $data['product_service_id'], 422, 'That is already your current plan.');

        $new = \App\Models\ProductService::withoutGlobalScopes()->find($data['product_service_id']);
        // Only within the same product group (matches the offered list).
        abort_if($sub->productService->category && $new->category !== $sub->productService->category, 422,
            'Please choose a plan from the same group.');

        $svc = app(\App\Services\Hosting\PlanChangeService::class);
        $charge = $svc->proratedCharge($sub, $new);

        if ($charge <= 0) {
            $svc->apply($sub, $new);

            $this->notifyStaffOfUpgrade($user->tenant_id, $hostingAccount, "Changed to {$new->name} (no charge)");

            return response()->json([
                'message' => "Plan changed to {$new->name} — your hosting package is being updated now.",
            ]);
        }

        $taxPercent = (float) ($new->tax_percent ?? 0);
        $taxAmount  = round($charge * $taxPercent / 100, 2);
        $total      = round($charge + $taxAmount, 2);

        $document = \Illuminate\Support\Facades\DB::transaction(function () use ($user, $sub, $new, $charge, $taxPercent, $taxAmount, $total) {
            // Supersede any earlier unpaid plan-change invoice.
            $priorDocId = $sub->metadata['pending_plan_change']['document_id'] ?? null;
            if ($priorDocId) {
                \App\Models\Document::withoutGlobalScopes()->where('id', $priorDocId)
                    ->whereNotIn('status', ['paid', 'cancelled'])->update(['status' => 'cancelled']);
            }

            $document = \App\Models\Document::withoutGlobalScopes()->create([
                'tenant_id'       => $user->tenant_id,
                'client_id'       => $user->client_id,
                'type'            => 'invoice',
                'document_number' => app(\App\Services\DocumentNumberService::class)->generate('invoice', $user->tenant_id),
                'date'            => now()->toDateString(),
                'due_date'        => now()->toDateString(),
                'subtotal'        => $charge,
                'discount_amount' => 0,
                'tax_amount'      => $taxAmount,
                'total'           => $total,
                'status'          => 'sent',
                'notes'           => "Plan upgrade: {$sub->productService->name} -> {$new->name} ({$sub->label})",
            ]);

            $document->items()->create([
                'item_type'   => 'service',
                'description' => "Upgrade to {$new->name} — prorated until " . ($sub->expire_date?->toDateString() ?? 'renewal'),
                'quantity'    => 1,
                'price'       => $charge,
                'tax_percent' => $taxPercent,
                'tax_amount'  => $taxAmount,
                'total'       => $total,
            ]);

            $sub->update(['metadata' => array_merge($sub->metadata ?? [], [
                'pending_plan_change' => [
                    'product_service_id' => $new->id,
                    'document_id'        => $document->id,
                ],
            ])]);

            return $document;
        });

        $this->notifyStaffOfUpgrade(
            $user->tenant_id,
            $hostingAccount,
            "Upgrade to {$new->name} requested — invoice {$document->document_number}",
            $document,
        );

        return response()->json([
            'data'    => ['document_id' => $document->id, 'document_number' => $document->document_number, 'total' => (float) $document->total],
            'message' => "Upgrade invoice {$document->document_number} created (Tsh." . number_format($total, 2) . ' prorated) — the upgrade applies automatically when it is paid.',
        ], 201);
    }

    private function notifyStaffOfUpgrade(
        string $tenantId,
        HostingAccount $hostingAccount,
        string $summary,
        ?\App\Models\Document $document = null,
    ): void {
        try {
            $staff = \App\Models\User::withPermission($tenantId, 'hosting.change_package');
            if ($staff->isNotEmpty()) {
                \Illuminate\Support\Facades\Notification::send(
                    $staff,
                    new \App\Notifications\HostingUpgradeRequestedNotification($hostingAccount, $summary, $document),
                );
            }
        } catch (\Throwable $e) {
            report($e);
        }
    }

    /** Change the cPanel password (portal admins only). */
    public function changePassword(Request $request, HostingAccount $hostingAccount)
    {
        $this->guardAccount($request, $hostingAccount);
        abort_unless($hostingAccount->status === 'active', 422, 'This hosting account is not active.');

        $data = $request->validate([
            'password' => 'required|string|min:12|max:64|confirmed',
        ]);

        try {
            (new WhmService($hostingAccount->server))
                ->forAccount($hostingAccount->id)
                ->resetPassword($hostingAccount->cpanel_username, $data['password']);

            // Security notice (never includes the password).
            try {
                $client = $hostingAccount->subscription?->client;
                $tenant = \App\Models\Tenant::withoutGlobalScopes()->find($hostingAccount->tenant_id);
                if ($client && $tenant && ($client->email || $client->phone)) {
                    $client->notify(new \App\Notifications\HostingPasswordChangedNotification($hostingAccount, $tenant, 'client portal'));
                }
            } catch (\Throwable $e) {
                \Illuminate\Support\Facades\Log::warning('Password-change notice failed', ['error' => $e->getMessage()]);
            }

            return response()->json(['message' => 'cPanel password changed.']);
        } catch (WhmApiException $e) {
            return response()->json(['message' => 'Password change failed: ' . $e->getMessage()], 422);
        }
    }

    /** Request cancellation — opens a support ticket for staff to action. */
    public function requestCancellation(Request $request, HostingAccount $hostingAccount)
    {
        $this->guardAccount($request, $hostingAccount);

        $data = $request->validate([
            'reason' => 'required|string|max:2000',
            'when'   => 'required|in:immediate,end_of_period',
        ]);

        $user = $request->user();
        $whenLabel = $data['when'] === 'immediate' ? 'Immediately' : 'At the end of the billing period';

        $ticket = \App\Models\Ticket::create([
            'tenant_id'     => $user->tenant_id,
            'client_id'     => $user->client_id,
            'ticket_number' => \App\Models\Ticket::nextNumber($user->tenant_id),
            'subject'       => "Cancellation request: {$hostingAccount->domain}",
            'status'        => 'open',
            'priority'      => 'high',
            'opened_by'     => $user->id,
            'last_reply_at' => now(),
        ]);

        $ticket->replies()->create([
            'tenant_id'      => $user->tenant_id,
            'author_type'    => 'client',
            'client_user_id' => $user->id,
            'message'        => "Service: {$hostingAccount->domain} ({$hostingAccount->cpanel_username})\nCancel: {$whenLabel}\n\nReason:\n{$data['reason']}",
        ]);

        try {
            foreach (\App\Http\Controllers\TicketController::staffToNotify($ticket) as $staff) {
                $staff->notify(new \App\Notifications\TicketActivityStaffNotification($ticket, 'opened'));
            }
        } catch (\Throwable) {
            // notification failure must not block the request
        }

        return response()->json([
            'message' => "Cancellation request submitted as ticket {$ticket->ticket_number} — our team will confirm shortly.",
        ], 201);
    }
}
