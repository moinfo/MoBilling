# Implementation Plan — WHMCS Exit: Hosting Provisioning + Domain Registrar + Data Import

> **Progress log**
> - **2026-07-03 — Workstream C BUILT & VERIFIED (not yet committed to production).**
>   WHMCS DB imported locally as `moinfote_billing` (184 tables); read-only `whmcs`
>   connection added to `config/database.php`; `legacy_id` + `clients.status/notes`
>   migration applied; `php artisan whmcs:import` implemented
>   (`app/Services/WhmcsImport/WhmcsImporter.php`) and dry-run-verified end-to-end:
>   122 products, 206 clients (**70 merged + 136 new**), 207 portal logins (bcrypt
>   carried over), 172 services, 1,052 invoices, 497 payments. Spot-verified client
>   Kassim Haji Kassim (tblclients.id=120): merged into his existing MoBilling row,
>   10 subscriptions with exact WHMCS renewal dates/prices, TZS 40.3M invoice history.
>   **Awaiting explicit go-live approval to run committed** (starts real billing +
>   requires disabling the WHMCS cron simultaneously).
> - **2026-07-03 — Workstream A backend implementation started** (see A-sections).

> The **execution companion** to the two design docs:
> - `WHM_CPANEL_INTEGRATION.md` (why/what — WHMCS exit, WHM provisioning, import mapping)
> - `DOMAIN_REGISTRAR_INTEGRATION.md` (why/what — .tz FRED-EPP via fred-client)
>
> This document is the **build checklist**: exact migrations, file paths, class
> skeletons, wiring points, and acceptance checks, in dependency order.
> Tick boxes as you go. Rationale lives in the design docs — not repeated here.

---

## 0. Conventions (follow the existing codebase)

Every new piece must match these established patterns:

| Concern | Convention | Reference example |
|---|---|---|
| Primary keys | `HasUuids` | any model |
| Tenancy | `BelongsToTenant` trait (global scope + auto tenant_id) | `app/Traits/BelongsToTenant.php` |
| Secrets in DB | `'encrypted'` / `'encrypted:array'` casts | — |
| Validation | inline `$request->validate()` or FormRequest; `Rule::exists(...)->where('tenant_id', $tenantId)` — **never bare `exists:`** | `StorePaymentInRequest` |
| Permissions | route middleware `permission:xxx.yyy`; seeded via defensive migration granted to every tenant's admin role | `2026_06_20_000003_seed_whatsapp_view_all_permission.php` |
| External HTTP | dedicated Service class using Laravel `Http`, per-tenant config, typed exceptions | `app/Services/WhatsAppService.php`, `TenantPesapalService.php` |
| Long-running external calls | queued jobs, retry with backoff — never inline in a request or billing loop | — |
| Cron | command registered in `routes/console.php`, `->dailyAt(...)->withoutOverlapping()`, result rows in `cron_logs` | `ProcessRecurringInvoices` |
| Money writes | `DB::transaction()` + `lockForUpdate()` | `PaymentInController::store` |
| Audit | append-only log table per domain | `cron_logs`, `communication_logs` |
| Frontend | Mantine + @tanstack/react-query; `usePermissions().can()`; invalidateQueries after mutations | `src/pages/WhatsappContacts.tsx` |

Queue note: provisioning/registrar jobs require a running queue worker. Verify
`QUEUE_CONNECTION` (if `sync`, jobs run inline — acceptable for MVP, but plan a
`database`/`redis` queue + supervisor before cutover).

---

## Workstream A — WHM/cPanel provisioning

### A0. Migrations

- [ ] `create_servers_table.php`
```php
Schema::create('servers', function (Blueprint $t) {
    $t->uuid('id')->primary();
    $t->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
    $t->string('name');
    $t->string('hostname');
    $t->unsignedInteger('port')->default(2087);
    $t->string('username');                    // root or reseller
    $t->text('api_token');                     // encrypted cast on model
    $t->json('nameservers')->nullable();
    $t->string('type')->default('whm_cpanel');
    $t->boolean('is_active')->default(true);
    $t->boolean('verify_ssl')->default(true);
    $t->timestamps();
    $t->index(['tenant_id', 'is_active']);
});
```
- [ ] `add_provisioning_to_product_services.php`
```php
Schema::table('product_services', function (Blueprint $t) {
    $t->string('provisioning_type')->default('none');   // none|whm_cpanel
    $t->foreignUuid('server_id')->nullable()->constrained('servers')->nullOnDelete();
    $t->string('cpanel_package')->nullable();
    $t->boolean('auto_provision')->default(false);
});
```
- [ ] `create_hosting_accounts_table.php`
```php
Schema::create('hosting_accounts', function (Blueprint $t) {
    $t->uuid('id')->primary();
    $t->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
    $t->foreignUuid('client_subscription_id')->constrained()->cascadeOnDelete();
    $t->foreignUuid('server_id')->constrained();
    $t->string('domain');
    $t->string('cpanel_username');
    $t->string('package')->nullable();
    $t->string('status')->default('pending');  // pending|active|suspended|terminated|failed
    $t->timestamp('last_synced_at')->nullable();
    $t->json('meta')->nullable();               // disk/bw snapshot, whm raw status
    $t->timestamps();
    $t->unique(['server_id', 'cpanel_username']);
    $t->index(['tenant_id', 'status']);
});
```
- [ ] `create_provisioning_logs_table.php` — `id, tenant_id, hosting_account_id nullable,
  server_id, action, request json (SANITIZED — no tokens/passwords), response json,
  status enum(success,failed), error text nullable, timestamps`. Index `(tenant_id, created_at)`.
- [ ] `seed_hosting_permissions.php` — permissions `menu.hosting`,
  `hosting.read`, `hosting.create`, `hosting.suspend`, `hosting.terminate`,
  `hosting.change_package`, `hosting.sso`, `hosting.settings`; grant all to every
  tenant's admin role (copy the whatsapp view_all seeder pattern).

### A1. Models
- [ ] `app/Models/Server.php` — HasUuids, BelongsToTenant; casts:
  `api_token => encrypted`, `nameservers => array`, booleans. Relation `hostingAccounts()`.
- [ ] `app/Models/HostingAccount.php` — relations: `subscription()`, `server()`; casts `meta => array`.
- [ ] `app/Models/ProvisioningLog.php`.
- [ ] `ProductService`: add new columns to `$fillable`, relation `server()`.
- [ ] `ClientSubscription`: add `hostingAccount()` hasOne.

### A2. `app/Services/WhmService.php`
Skeleton (copy structure from `WhatsAppService`):
```php
class WhmService
{
    public function __construct(private Server $server) {}

    private function call(string $fn, array $params = []): array
    {
        $req = Http::withHeaders([
                'Authorization' => "whm {$this->server->username}:{$this->server->api_token}",
            ])->timeout(30);
        if (!$this->server->verify_ssl) $req = $req->withoutVerifying();

        $res = $req->get("https://{$this->server->hostname}:{$this->server->port}/json-api/{$fn}", 
                         $params + ['api.version' => 1]);

        $json = $res->json();
        // WHM API 1: metadata.result 1 = success
        if (!$res->ok() || (($json['metadata']['result'] ?? 0) != 1)) {
            throw new WhmApiException($fn, $json['metadata']['reason'] ?? $res->body());
        }
        return $json;
    }

    public function listPackages(): array;                       // listpkgs
    public function accountSummary(string $user): array;         // accountsummary
    public function createAccount(array $p): array;              // createacct
    public function suspend(string $user, string $reason = ''): array;
    public function unsuspend(string $user): array;
    public function terminate(string $user): array;              // removeacct
    public function changePackage(string $user, string $pkg): array;
    public function resetPassword(string $user, string $pw): array;
    public function ssoUrl(string $user): string;                // create_user_session (service=cpaneld)
}
```
- [ ] `app/Exceptions/WhmApiException.php`
- [ ] Every public method writes a `ProvisioningLog` row (success or failure).
  Sanitize: never persist `password` or the token.

### A3. Lifecycle hook — observer + jobs
- [ ] `app/Observers/ClientSubscriptionObserver.php`, registered in `AppServiceProvider::boot()`:
```php
public function updated(ClientSubscription $sub): void
{
    if (!$sub->wasChanged('status')) return;
    $product = $sub->productService;
    if (!$product || $product->provisioning_type !== 'whm_cpanel') return;

    match ($sub->status) {
        'active'    => $sub->hostingAccount
                        ? ReactivateHostingAccount::dispatch($sub->hostingAccount)
                        : ($product->auto_provision ? ProvisionHostingAccount::dispatch($sub) : null),
        'suspended' => $sub->hostingAccount ? SuspendHostingAccount::dispatch($sub->hostingAccount) : null,
        'cancelled' => $sub->hostingAccount ? TerminateHostingAccount::dispatch($sub->hostingAccount) : null,
        default     => null,
    };
}
```
- [ ] Jobs in `app/Jobs/Hosting/`: `ProvisionHostingAccount`, `SuspendHostingAccount`,
  `ReactivateHostingAccount`, `TerminateHostingAccount`, `ChangeHostingPackage`.
  Each: `tries=3`, `backoff=[60,300,900]`, sets `hosting_accounts.status` (`failed` on
  final failure), logs, and on provision sends the welcome notification.
- [ ] `ProvisionHostingAccount` specifics: generate username from domain (WHM rules:
  ≤16 chars, starts with letter, no reserved names), generate strong password
  (never stored — used once in `createacct`, then included in the welcome email or,
  better, omitted in favor of an SSO link), read `domain` from a new
  `ClientSubscription.metadata['domain']` (set in the subscription form when the
  product is a hosting product).
- [ ] `app/Notifications/HostingAccountProvisionedNotification.php` (mail; reuse
  `HasTenantBranding`).

### A4. HTTP API + routes (`routes/api.php`)
- [ ] `ServerController` — CRUD + `POST /servers/{server}/test` (calls `listPackages`,
  returns package names). Middleware `permission:hosting.settings`.
- [ ] `HostingAccountController`:
  - `GET /hosting-accounts` (tenant list, filters) — `hosting.read`
  - `POST /client-subscriptions/{sub}/provision` (manual create) — `hosting.create`
  - `POST /hosting-accounts/{acc}/suspend|unsuspend` — `hosting.suspend`
  - `POST /hosting-accounts/{acc}/terminate` — `hosting.terminate`
  - `POST /hosting-accounts/{acc}/change-package` — `hosting.change_package`
  - `POST /hosting-accounts/{acc}/sso` → `{url}` — `hosting.sso`
  - `GET  /hosting-accounts/{acc}/logs` — `hosting.read`
- [ ] Portal: `GET /portal/hosting` (client's accounts) + `POST /portal/hosting/{acc}/sso`
  (verify the account belongs to the authed portal user's client).

### A5. Scheduled reconcile
- [ ] `app/Console/Commands/ReconcileHostingAccounts.php` — `hosting:reconcile`:
  per active server → `accountsummary` per account (batch), fix status drift
  (registry wins), refresh `meta.disk/bw`, retry `failed`, write `CronLog`.
- [ ] Register: `Schedule::command('hosting:reconcile')->dailyAt('05:30')->withoutOverlapping();`

### A6. Frontend (mobilling-ui)
- [ ] `src/api/hosting.ts` — types + endpoints above.
- [ ] Settings → **Servers** tab (CRUD + Test connection showing package list).
- [ ] Product form: provisioning section (type, server select, package select via test
  results, auto-provision switch) — only when `type=service`.
- [ ] Subscription detail / client profile: **Hosting panel** (status badge, domain,
  username, package, usage, action buttons per permission, log viewer drawer).
- [ ] Portal UI: "My Hosting" card + Login to cPanel button.

### A7. Acceptance (Workstream A done when)
- [ ] "Test connection" lists packages from a real WHM box.
- [ ] Paying the first invoice of an auto-provision product creates a real cPanel
  account ≤60s later; welcome mail sent; `hosting_accounts` row `active`.
- [ ] `subscriptions:suspend-unpaid` suspending a subscription suspends the cPanel
  account; paying reactivates it; manual cancel terminates it.
- [ ] SSO button lands an authenticated cPanel session.
- [ ] Killing the WHM box mid-flow → job retries, then `failed` status + visible log;
  billing unaffected.
- [ ] `hosting:reconcile` corrects a manually-suspended (via WHM UI) account's status.

---

## Workstream B — Domain registrar (.tz FRED-EPP)

### B0. Prerequisites (fred-client side — do first)
- [ ] Fix `verify=False` in `backend/apps/registry/epp_client.py` (verify/pin TZNIC CA).
- [ ] Add service-token auth middleware to the Django REST API; bind to
  localhost/private interface (it must not be internet-facing).
- [ ] Confirm with TZNIC/TCRA whether `mtanzania.tznic.or.tz` is production or OT&E;
  record in `registrar_accounts.is_sandbox`.
- [ ] Smoke-test manually: `check` a domain, `credit` query.

### B1. Migrations (unganisha-api)
- [ ] `create_registrar_accounts_table.php` — per design doc §5: **`tenant_id nullable`**
  (NULL = platform account), `driver` (`fred_epp`), `endpoint_url`, `registrar_id`,
  `credentials` (encrypted:array — service token, EPP password ref), `cert_path`,
  `key_path`, `is_active`, `is_sandbox`.
  ⚠ `BelongsToTenant` global scope would hide the platform row — this model must NOT
  use the trait blindly; scope manually (`where(tenant_id)->orWhereNull(tenant_id)` in
  the resolver).
- [ ] `create_domain_tlds_table.php` — `tenant_id nullable` (platform=base cost,
  tenant=retail), `tld`, `register_price`, `renew_price`, `transfer_price`,
  `years_min/max`, `is_active`. Unique `(tenant_id, tld)`.
- [ ] `create_domains_table.php` — per design doc §5. Key columns: `tenant_id`,
  `client_id`, `registrar_account_id`, `name` (globally unique), `status`,
  contact handles, `nsset_handle`, `keyset_handle`, `registered_at`, `expires_at`,
  `auto_renew`, `epp_auth_info` (encrypted), `meta` json, `legacy_id`.
  Indexes: `(tenant_id, expires_at)`, `(tenant_id, status)`.
- [ ] `create_domain_logs_table.php` — mirror `provisioning_logs`.
- [ ] `seed_domain_permissions.php` — `menu.domains`, `domains.read/create/renew/
  transfer/manage_dns/settings`; admin-role grant per tenant.

### B2. Driver layer
- [ ] `app/Contracts/RegistrarDriver.php` — interface per design doc §6.
- [ ] `app/Services/Registrar/FredHttpDriver.php` — Laravel `Http` → Django API
  (`/api/domains/check`, `.../register`, `.../{name}/renew|info`, nsset/keyset
  endpoints, `/api/billing/credit/`), Bearer service token, typed
  `RegistrarApiException`, every call → `DomainLog`.
- [ ] `app/Services/Registrar/DomainRegistrarManager.php` — resolves the tenant's
  `registrar_account` (fallback platform row), builds driver, exposes the interface.

### B3. Billing wiring
- [ ] **Order → invoice:** `DomainController@order` — validate availability
  (`check`), price from `domain_tlds` (tenant retail, fallback platform), create a
  `Document` invoice with a domain line item, create `domains` row `status=pending`
  linked via `meta.document_id`.
- [ ] **On payment:** extend the paid-invoice hook (same place subscriptions activate,
  `PaymentInController`) — if the document references a pending domain →
  `RegisterDomainJob::dispatch($domain)`; if a renewal invoice →
  `RenewDomainJob`.
- [ ] Jobs `app/Jobs/Domains/`: `RegisterDomainJob` (ensure registrant contact handle
  exists — create from Client record if missing — then domain create, sync
  `expires_at`, notify), `RenewDomainJob`, `TransferDomainJob`, `SyncDomainJob`.
- [ ] Commands:
  - `domains:process-renewals` (dailyAt 06:30) — auto_renew domains expiring ≤45d
    without an open renewal invoice → generate invoice (existing reminder ladder
    covers the rest). CronLog.
  - `domains:sync` (dailyAt 05:45) — `info` every non-cancelled domain, reconcile
    status/expiry; refresh registrar credit; low-credit alert (mail + WhatsApp to
    tenant admin / platform owner). CronLog.
- [ ] Notifications: `DomainRegisteredNotification`, `DomainRenewalReminderNotification`
  (if not fully covered by the invoice ladder), `DomainExpiredNotification`.

### B4. HTTP API + routes
- [ ] `GET /domains/check?name=` — `domains.read`
- [ ] `GET /domains` (list, filters), `GET /domains/{domain}` (+logs) — `domains.read`
- [ ] `POST /domains/order` (register or transfer-in w/ auth_info) — `domains.create` / `domains.transfer`
- [ ] `POST /domains/{domain}/renew` (manual, creates invoice) — `domains.renew`
- [ ] `PUT /domains/{domain}/nameservers`, `PUT /domains/{domain}/dnssec` — `domains.manage_dns`
- [ ] `GET /domains/{domain}/auth-info` (reveal, audited) — `domains.transfer`
- [ ] Settings: `registrar-accounts` CRUD + `POST .../test` (credit query) — `domains.settings`;
  `domain-tlds` CRUD — `domains.settings`
- [ ] Portal: `GET /portal/domains`, `POST /portal/domains/{domain}/renew` (invoice →
  existing pay page), optional nameserver self-service behind a tenant toggle.

### B5. Frontend
- [ ] `src/api/domains.ts`; Domains page (list + expiry badges + search/filters);
  register/transfer wizard (check → client → years → invoice); domain detail
  (NS/DNSSEC/auth-info/renewals/logs); Settings tabs (Registrar Accounts, TLD Pricing);
  portal "My Domains".

### B6. Acceptance (Workstream B done when)
- [ ] Settings "Test connection" returns live registry credit.
- [ ] Order + pay a .tz domain end-to-end → real EPP registration → `expires_at`
  matches registry `info`.
- [ ] `domains:process-renewals` generates a renewal invoice 45d out; paying it renews
  at the registry and advances `expires_at`.
- [ ] Unpaid renewal: nothing destructive happens; after registry expiry,
  `domains:sync` flips status to `expired`.
- [ ] A second tenant sees only its own domains; retail price overrides work.
- [ ] Low registry credit fires the alert.

---

## Workstream C — WHMCS importer

### C0. Prep — ✅ DONE 2026-07-03
- [x] WHMCS dump (168MB) imported locally as DB `moinfote_billing`; `whmcs` connection
  added in `config/database.php` (env `WHMCS_DB_*`, defaults to the local copy).
- [x] Schema verification run. Actual values: client status Active/Inactive only;
  service status Pending/Active/Suspended/Terminated/Cancelled; cycles Annually(161)/
  Monthly(6)/Quarterly(4)/One Time(1) — **no biennial/triennial**; invoice status
  Paid/Cancelled/Unpaid/Refunded; single currency **TZS**; all 476 transactions
  gateway=`pesapal`; **all 331 login hashes bcrypt (`$2y$`)**; 1 WHM server; 171/197
  domains on the `fred` registrar module.
- [x] `2026_07_03_000000_add_whmcs_import_columns.php` — `legacy_id` on clients,
  client_users, product_services, client_subscriptions, documents, payments_in
  (+ `clients.status`, `clients.notes`). `domains`/`servers`/`hosting_accounts` get
  theirs in their own create-migrations (Workstreams A/B).

### C1. Command: `php artisan whmcs:import`
```
whmcs:import --tenant=<uuid> [--stage=all|servers|products|clients|users|services|invoices|payments|domains]
             [--dry-run] [--limit=N]
```
Structure: `app/Console/Commands/WhmcsImport.php` orchestrating one Importer class
per stage in `app/Services/WhmcsImport/` — each idempotent (`updateOrCreate` keyed on
`legacy_id`), chunked (500 rows), wrapped per-chunk in a transaction, writing an
import report (counts, skips w/ reasons) to storage + `CronLog`.

Stage order & core mappings (details in design doc §6):
- [ ] **servers**: `tblservers` → `servers` (WHM boxes; API tokens entered manually after).
- [ ] **products**: `tblproducts`+`tblpricing` → `product_services`.
  Cycle map incl. `Semi-Annually→half_yearly`; biennial/triennial → per decision Q4.
  `servertype='cpanel'` → `provisioning_type='whm_cpanel'` + package from configoption.
- [ ] **clients**: `tblclients` → `clients`. Dedupe against `(tenant_id,email)` and
  `(tenant_id,phone)` — collision policy: keep first, blank the dup field on later
  rows, record in report. Flatten address. `notes` → new clients.notes column.
- [ ] **users**: `tblusers`(+`tblusers_clients`) or `tblclients.password` (pre-8) →
  `client_users` — **copy bcrypt hash as-is**; shared logins → one row per client;
  legacy md5 hashes → random password + report (OTP re-registration covers them).
- [ ] **services**: `tblhosting` → `client_subscriptions`
  (status map Pending/Active/Suspended→same; Terminated/Cancelled/Fraud/Completed→`cancelled`;
  raw kept in `metadata.whmcs_status`; **`amount` = price source**, `nextduedate` →
  `expire_date`, domain → `label` + `metadata.domain`) + `hosting_accounts`
  (username/domain/server, status mapped; do NOT import passwords).
  ⚠ Promo check: compare `amount` vs last renewal invoice total; mismatches → report.
- [ ] **invoices**: `tblinvoices`+`tblinvoiceitems` → `documents`+`document_items`
  (status map per design doc §6.2; skip or specially-tag `AddFunds` invoices;
  document numbers: keep MoBilling sequence, store WHMCS number in notes/meta).
- [ ] **payments**: `tblaccounts` (amountin>0) → `payments_in`
  (`gateway`→`payment_method` map, `transid`→`reference`); refunds (`amountout`) →
  report only (no refund model — decision Q-credit).
- [ ] **domains**: `tbldomains` → `domains` (per Workstream B; requires B1 first).
- [ ] Post-import reconciliation artisan check `whmcs:import-verify`:
  row counts per stage, Σ invoice totals, Σ payments, unpaid-balance comparison,
  spot-check N random clients. Output table + non-zero exit on mismatch.

### C1.1 Implementation decisions made (differ from / extend the original spec)
- **Client MERGE strategy** (added after spot-check): 67+ WHMCS clients already exist
  as MoBilling clients (tenant ran both systems in parallel). The importer matches
  existing clients by email or digit-normalized phone and **adopts** them (sets
  `legacy_id`, fills only blank fields, keeps the MoBilling identity) instead of
  creating duplicates. Verified with Kassim Haji Kassim (tblclients.id=120).
- Invoice numbering: always `WHMCS-{tblinvoices.id}` (the optional `invoicenum` can
  collide with another invoice's id); original number preserved in notes.
- Credit-paid invoices get a **synthesized `payment_method='credit'` PaymentIn** so
  `balance_due` reaches zero (33 rows).
- `document_items.description` is varchar(255) → long WHMCS lines are whitespace-
  collapsed and truncated to 250 chars.
- Per-service price overrides (`tblhosting.amount` ≠ catalog) produce **variant
  ProductService rows** (code `WHMCS-P{pid}-{cycle}-{amount}`) so renewals bill the
  real price.
- Billing anchor: subscription `start_date` is set one cycle before `nextduedate`
  so `RecurringInvoiceService`'s date-walk lands exactly on the WHMCS renewal date;
  the true registration date is kept in `metadata.whmcs_regdate`.
- 126 WHMCS logins with no client link (orphan registrations) and 12 payments
  referencing deleted clients are intentionally skipped (reported).

### C2. Acceptance (Workstream C done when)
- [x] Consecutive dry-runs produce identical results (idempotent via `legacy_id`).
- [x] Spot-verification passed (client 120: merge, subscriptions, totals).
- [ ] **Committed run into the production tenant** — awaiting explicit approval
  (starts real billing; disable the WHMCS cron at the same time).
- [ ] A migrated client logs into the MoBilling portal with their old WHMCS password
  and sees their services, invoices, and domains.

---

## Workstream D — Cutover (runbook)

- [ ] Freeze code; deploy all workstreams to production behind permissions.
- [ ] Announce maintenance window to clients.
- [ ] **Disable WHMCS cron** (no more invoice generation / suspensions there).
- [ ] Final `whmcs:import` run (delta via idempotency) + `whmcs:import-verify`.
- [ ] Point provisioning products at real servers; enable `auto_provision`.
- [ ] Verify: 1 test registration, 1 renewal payment, 1 suspend/unsuspend round-trip,
  1 cPanel SSO, 1 domain renewal — on production.
- [ ] Switch client links/emails to the MoBilling portal (logins carry over).
- [ ] WHMCS → read-only for 2 weeks (reference), then decommission; revoke the
  read-only DB user; archive a final dump.
- [ ] Retire `fred-client/whmcs` module; decide fate of the Next.js storefront (Q1).

---

## Sequencing & rough effort

```
Week 1   A0–A3 (WHM schema+service+jobs)      B0 (fred-client hardening) — parallel
Week 2   A4–A7 (API+UI+reconcile+acceptance)  B1–B2 (schema+driver)
Week 3   B3–B6 (billing wiring+UI+acceptance) C0 (legacy_id + WHMCS access)
Week 4   C1 importer + staging rehearsal #1
Week 5   rehearsal #2 + fixes; portal/UX polish
Week 6   D cutover + parallel-run monitoring
```
Solo-dev estimate; parallelize A and B if two people. Every phase ends deployable —
nothing blocks existing billing at any point.

## Blocking decisions (answer before the workstream that needs them)

| # | Question | Blocks | Status |
|---|---|---|---|
| 1 | Biennial/triennial WHMCS cycles | C1 products | ✅ RESOLVED by data: none exist |
| 2 | Client credit balances | C1 payments | ✅ RESOLVED by data: 3 clients / TZS 175k — synth-credit payments cover applied credit; residual balances handled manually |
| 3 | Terminate policy: immediate `removeacct` or suspend-then-delete after N days? | A3 | OPEN — implementation defaults to **suspend on cancel; terminate is a manual admin action** (safest; change later if desired) |
| 4 | Support tickets: build later or external helpdesk at cutover? | D comms | Effectively resolved: only 11 tickets — archive, decide later |
| 5 | moinfo.tz storefront: keep or retire? | B/Phase 3 | OPEN |
| 6 | `mtanzania.tznic.or.tz` — production or OT&E? | B0 | OPEN — confirm with TZNIC/TCRA |
| 7 | Queue driver for production (database/redis + supervisor)? | A3/B3 | OPEN — check `QUEUE_CONNECTION`; sync is acceptable for MVP |
