# WHMCS → MoBilling: Full Migration Plan (incl. WHM/cPanel Provisioning)

> Goal: **leave WHMCS entirely** — move clients, products, services, invoices, payments,
> the client portal, and hosting provisioning into MoBilling — so we stop paying WHMCS
> license fees while keeping the same customer experience: auto-created hosting accounts,
> suspend on non-payment, reactivate on payment, terminate on cancellation, online
> invoice payment, and one-click cPanel login.
>
> This document was produced from a full audit of the MoBilling codebase (5 parallel
> code/domain surveys) + WHMCS schema research. File references point at real code.

---

## 1. The big picture

WHMCS is three things bolted together:

1. **A billing system** — clients, products, recurring invoices, payments, dunning.
2. **A client portal** — login, view/pay invoices, manage services.
3. **Provisioning modules** — code that calls the **WHM API** to manage cPanel accounts.

The audit found MoBilling **already has (1) and (2) almost completely** — including
things we assumed were missing (a full client portal with online payment, a public
pay-this-invoice page, automated late fees and multi-stage dunning). The genuinely
missing pieces are:

- **(3) WHM/cPanel provisioning** — the adapter this doc specifies (§5).
- **A data importer** from the WHMCS database (§6).
- A handful of billing parity gaps (§4) — most optional for cutover.

> **License note:** this removes the *WHMCS* fee only. The **cPanel/WHM license on the
> hosting server stays** — that's cPanel's product cost, unrelated to WHMCS.

---

## 2. What MoBilling already has (audited, with file refs)

### Billing engine ✅
| Capability | Where |
|---|---|
| Products/services catalog (5 billing cycles: once/monthly/quarterly/half_yearly/yearly) | `app/Models/ProductService.php` |
| Client subscriptions (`pending / active / suspended / cancelled`, `start_date`, `expire_date` = paid-through, `metadata` json) | `app/Models/ClientSubscription.php` |
| Recurring invoice generation — 30 days before due, deduped per cycle | `app/Services/RecurringInvoiceService.php` + `RecurringInvoiceLog` |
| Payment reminders at 21/14/7/3/1 days before due | same service, `reminders_sent` json |
| Activate subscription + advance paid-through date on payment | `PaymentInController::activateLinkedSubscriptions()` |
| Suspend on unpaid past grace period (per-tenant `subscription_grace_days`, default 7) | `app/Console/Commands/SuspendUnpaidSubscriptions.php` (daily 09:30) |
| Overdue dunning ladder: mark overdue → **auto late fee** (tenant %) → 7-day reminder → 14-day termination warning | `app/Console/Commands/ProcessOverdueInvoices.php` (daily 08:30) |
| Quotation → proforma → invoice pipeline, per-tenant numbering (`INV-YYYY-0001`), PDF (dompdf), per-line tax & discounts, partial payments | `Document*`, `PdfService`, `DocumentNumberService` |
| Scheduler verified live (system cron → `schedule:run`, healthy `cron_logs`) | `routes/console.php` |

### Payments ✅ (customer-initiated)
| Capability | Where |
|---|---|
| **Public pay page** — customer pays an invoice with no login: `GET /pay/{document}` → Pesapal hosted checkout | `routes/api.php`, `InvoicePaymentController` |
| Per-tenant Pesapal credentials (each tenant collects into their own account) | `TenantPesapalService`, `Tenant.pesapal_*`, `TenantPesapalWebhookController` |
| IPN verified server-side → creates `PaymentIn` → flips invoice `paid`/`partial` → activates subscriptions | `TenantPesapalWebhookController::ipn` |
| Manual payment recording by staff (+ emailed receipt PDF) | `PaymentInController` |

### Client portal ✅ (bigger than expected)
| Capability | Where |
|---|---|
| Separate client logins (`client_users`: email+password per tenant, roles admin/viewer) | `app/Models/ClientUser.php` |
| Sanctum-auth `/portal` routes: dashboard, documents, **pay online**, payment history + receipts, statement, products, subscriptions, profile, password | `routes/api.php` ~L570-591, `Portal/*` controllers |
| **Self-registration via OTP** (`/portal/request-otp`, `/portal/verify-register`) | `Portal/PortalAuthController` |
| Staff-side portal user management + impersonation | `clients.portal_login` permission |

### Communications ✅ (outbound)
| Capability | Where |
|---|---|
| Email + **SMS** (generic HTTP gateway, per-tenant sender/auth, metered SMS credit) + **WhatsApp** (Meta Cloud API, per-tenant token) | `SmsService`, `WhatsAppService`, `WhatsAppChannel` |
| ~30 notifications: invoice sent/overdue/late-fee/termination-warning/cancelled, receipts, suspension, portal OTP… | `app/Notifications/` |
| Tenant-editable templates for the 4 key client messages (placeholders: `{doc_number}`, `{client_name}`, `{amount}`, …) | `ReminderTemplateService`, Settings → Templates |
| Full send/fail audit log per client | `CommunicationLog` + listeners |
| Mass broadcast (email/SMS, client filtering, history) | `BroadcastController` |

---

## 3. What WHMCS does that MoBilling does NOT (gap analysis)

### Must-have for cutover
| Gap | Notes | Effort |
|---|---|---|
| **WHM/cPanel provisioning** | The core of this doc — §5 | Days |
| **WHMCS data importer** | §6 — clients, services, invoices, credit | Days |
| `legacy_id` (WHMCS id) columns | For idempotent re-runs + reconciliation | Trivial |
| Client-level status / notes | WHMCS has Active/Inactive/Closed + admin notes; `clients` table has neither | Small |

### Decide-per-business (can follow cutover)
| Gap | Notes | Effort |
|---|---|---|
| Support **tickets / helpdesk / knowledgebase** | Definitively absent in MoBilling — client comms are outbound-only. Either build, or use an external desk (e.g. free tier of a helpdesk) | Large |
| **Domain registration/renewal** | Goes to registries/registrars, *not* WHM. For **.tz** we already have a near-complete FRED-EPP registrar portal (`/var/www/html/fred-client`, REG-MOINFOTECH) — plan: **`docs/DOMAIN_REGISTRAR_INTEGRATION.md`**. `tbldomains` imports into the new `domains` table there | Medium (plan exists) |
| Client **credit balance / wallet** | WHMCS `tblclients.credit` has no home; MoBilling has no credit/refund/credit-note concept | Medium |
| **Card-on-file auto-capture** | MoBilling never auto-charges — every payment is a Pesapal redirect or manual. WHMCS auto-billing tokens (`subscriptionid`) can't carry over to Pesapal's hosted flow | Large (needs tokenizing gateway) |
| Setup fees, per-cycle pricing, biennial/triennial cycles | `ProductService` = one price, 5 cycles. Split multi-cycle WHMCS products into separate rows, or extend schema | Small–Medium |
| Product **addons / configurable options** | Model each addon as its own `ProductService`+`ClientSubscription` (invoices already group per client); config options → `metadata` json | Small (workaround) |
| **Proration / upgrade-downgrade credit** | Whole-cycle billing only | Medium |
| Recurring promos / coupons | Subscription discount applies to **first invoice only** | Medium |
| Multi-currency | Single currency per tenant (`Tenant.currency`) | Medium |
| More gateways (Stripe/PayPal) | Pesapal only today (it does aggregate M-Pesa/Airtel/cards) | Medium |

---

## 4. Architecture for the new pieces

```
                       ┌────────────────────────────────┐
 Billing lifecycle     │  MoBilling (existing)           │
 (already built)       │  ClientSubscription status      │
       │               │  Invoices / Payments / Portal   │
       │ status change └───────────────┬────────────────┘
       ▼                               │
 ClientSubscription observer ──────────┘   (single place; dispatches queued jobs)
       │
       ▼
  WhmService (HTTP) ──► https://server:2087/json-api/* ──► WHM / cPanel
       │
       ▼
  hosting_accounts (state) + provisioning_logs (audit)

  WHMCS MySQL (read-only) ──► whmcs:import artisan command ──► MoBilling tables
```

---

## 5. WHM/cPanel provisioning integration

### 5.1 How the WHM API works
Authenticated HTTPS to the WHM server, port **2087**:

```
https://<server-host>:2087/json-api/<function>
Header:  Authorization: whm <user>:<API_TOKEN>
```

Token from WHM → *Development » Manage API Tokens* (prefer a **reseller** token over root).

| Purpose | WHM API 1 function |
|---|---|
| Create account | `createacct` (username, domain, password, `plan`, contactemail) |
| Suspend / un-suspend | `suspendacct` / `unsuspendacct` |
| Terminate | `removeacct` |
| Change package | `changepackage` |
| Reset password | `passwd` |
| One-click cPanel SSO | `create_user_session` → one-time login URL |
| Status / usage | `accountsummary`, `listaccts` |
| Packages | `listpkgs`, `addpkg` |

### 5.2 New data model

**`servers`** — one row per WHM box
`id, tenant_id, name, hostname, port(2087), username, api_token(ENCRYPTED cast),
nameservers(json), type('whm_cpanel'), is_active, verify_ssl`

**`product_services`** — add columns
`provisioning_type enum('none','whm_cpanel')`, `server_id?`, `cpanel_package?`, `auto_provision bool`

**`hosting_accounts`**
`id, tenant_id, client_subscription_id, server_id, domain, cpanel_username, package,
status enum(pending,active,suspended,terminated,failed), last_synced_at, meta(json)`
> Passwords are **never stored** — SSO via `create_user_session`; resets via `passwd`.

**`provisioning_logs`** — append-only audit (mirrors the `cron_logs` pattern):
`hosting_account_id, action, request(sanitized), response, status, error, timestamps`

### 5.3 `WhmService`
Copy the pattern of `app/Services/WhatsAppService.php` (Laravel `Http`, per-tenant creds):

```php
class WhmService {
    public function __construct(Server $server) {}
    public function createAccount(array $p): array;              // createacct
    public function suspend(string $user, string $reason=''): array;
    public function unsuspend(string $user): array;
    public function terminate(string $user): array;              // removeacct
    public function changePackage(string $user, string $pkg): array;
    public function resetPassword(string $user, string $pw): array;
    public function ssoUrl(string $user): string;                // create_user_session
    public function accountSummary(string $user): array;
    public function listPackages(): array;                       // "Test connection"
}
```
- `Authorization: whm {user}:{token}` header; honor `verify_ssl` (WHM self-signed certs).
- Log every call to `provisioning_logs`; never log tokens/passwords.
- Throw typed `WhmApiException` so queued jobs can retry with backoff.

### 5.4 Lifecycle hook points (⚠ corrected by the audit)

Dispatch **queued jobs** on `ClientSubscription` status transitions so a slow WHM box
never blocks billing. Put the mapping in ONE place — a model **observer** on the
`status` attribute (audit finding: transitions currently happen in three different
files, and manual `cancelled` via `ClientSubscriptionController::update()` is one of them).

| Transition | Job | WHM call |
|---|---|---|
| `pending` → `active` (first activation, product has `auto_provision`) | `ProvisionHostingAccount` | `createacct` → save account → welcome email |
| `suspended` → `active` | `ReactivateHostingAccount` | `unsuspendacct` |
| `active` → `suspended` | `SuspendHostingAccount` | `suspendacct` |
| any → `cancelled` | `TerminateHostingAccount` | `removeacct` (optionally suspend-then-terminate after N days grace) |
| package change | `ChangeHostingPackage` | `changepackage` |

Where transitions fire today:
- **Activate:** `PaymentInController::activateLinkedSubscriptions()` (on invoice paid).
- **Suspend:** `SuspendUnpaidSubscriptions` command (daily 09:30).
- **Cancel:** *manual only* — `ClientSubscriptionController::update()`.

> ⚠ **Do NOT hook `subscriptions:expire` / `ExpireSubscriptions`** — the audit confirmed
> that command operates on **`TenantSubscription`** (MoBilling's own SaaS billing of its
> tenants), *not* client subscriptions. Client subs have **no** `expired` status and
> nothing auto-cancels them; `expire_date` is a paid-through marker only. The observer
> approach also future-proofs any new cancellation paths.

### 5.5 Reconcile
`php artisan hosting:reconcile` (daily, register in `routes/console.php`):
compare `listaccts`/`accountsummary` vs `hosting_accounts`, fix drift, refresh
disk/bandwidth into `meta`, retry `failed` accounts, alert on mismatches.

### 5.6 UI
- **Admin:** Settings → Servers (CRUD + "Test connection" via `listpkgs`); product form
  provisioning fields; per-subscription hosting panel (domain/user/package/usage,
  manual create/suspend/unsuspend/terminate/change-package/reset-password, log viewer).
- **Client portal:** "My Hosting" (domain, package, usage) + **"Login to cPanel"**
  button → `ssoUrl()` redirect. Slots into the existing portal (§2).

---

## 6. Data migration from WHMCS

### 6.1 Source: the WHMCS database (key tables)

WHMCS MySQL has **no foreign keys** — relations by convention. Core tables:

| WHMCS table | Contents | Migrates to |
|---|---|---|
| `tblclients` | Client billing entities (name, email, address, `currency`, `credit`, `status`, notes) | `clients` |
| `tblusers` + `tblusers_clients` (WHMCS 8) | **Login identities** (email, bcrypt password); one user ↔ many clients | `client_users` |
| `tblcontacts` | Sub-contacts (some with portal login + permissions) | `client_users` (role-mapped) |
| `tblproducts` + `tblpricing` | Catalog; **prices live in `tblpricing`** (per-cycle columns, −1 = disabled) | `product_services` |
| `tblhosting` | Service instances — see §6.3 | `client_subscriptions` + `hosting_accounts` |
| `tblhostingaddons` | Product addons billed with a service | extra `client_subscriptions` |
| `tblinvoices` + `tblinvoiceitems` | Invoices; line `type`+`relid` polymorphic (Hosting/Domain/Addon/LateFee/PromoHosting/AddFunds…) | `documents` + `document_items` |
| `tblaccounts` | Payment ledger (`amountin`, `amountout`=refunds, `rate` FX, gateway, transid) | `payments_in` |
| `tbldomains` | Domain registrations (registrar module, expiry, `nextduedate`) | see gap §3 — minimally `client_subscriptions` |
| `tblcredit` / `tblclients.credit` | Credit change log / authoritative balance | ⚠ no MoBilling home — decide (§3) |
| `tblcustomfields` + `tblcustomfieldsvalues` | Custom fields (`relid` polymorphic: client id vs service id!) | `ClientSubscription.metadata` / new columns |
| `tbltickets` + `tblticketreplies` | Support tickets | ⚠ no home — export/archive, or new module |
| `tblorders` | Order history (audit only — hosting/domains are source of truth) | optional archive |

### 6.2 Status & cycle mappings

| WHMCS | Values | MoBilling mapping |
|---|---|---|
| Client status | `Active / Inactive / Closed` | no column today → add one, or Active→row, Closed→soft-delete |
| Service status (`tblhosting.domainstatus` — yes, that's its name) | `Pending / Active / Suspended / Terminated / Cancelled / Fraud / Completed` | `pending / active / suspended / cancelled / cancelled / cancelled / cancelled` *(lossy — keep original in `metadata.whmcs_status`)* |
| Invoice status | `Draft / Unpaid / Paid / Cancelled / Refunded / Collections / Payment Pending` | `draft / sent-overdue / paid / cancelled / cancelled+note / overdue / sent` |
| Billing cycle | `Monthly / Quarterly / Semi-Annually / Annually / Biennially / Triennially / One Time / Free Account` | `monthly / quarterly / half_yearly / yearly / ⚠none / ⚠none / once / once` — biennial/triennial: extend enum or normalize to yearly with doubled/tripled price |

Run `SELECT DISTINCT` on every enum-ish column before writing mappers — old installs
accumulate oddball values.

### 6.3 `tblhosting` → subscription + hosting account

| WHMCS field | Target |
|---|---|
| `userid`, `packageid` | `client_id`, `product_service_id` (via legacy-id maps) |
| `domain` | `ClientSubscription.label` + `hosting_accounts.domain` |
| `username` | `hosting_accounts.cpanel_username` |
| `server` (→`tblservers`) | `hosting_accounts.server_id` (import `tblservers` → `servers` first) |
| `regdate` | `start_date` |
| **`nextduedate`** | `expire_date` (paid-through anchor) — see gotcha below |
| **`amount`** | effective recurring price — **use this, not the catalog price** (admins override per-service) |
| `domainstatus` | status per §6.2 |
| `password` (AES-encrypted) | decrypt via WHMCS local API **`DecryptPassword`** if needed for continuity — but prefer NOT storing it (MoBilling uses SSO) |

### 6.4 Passwords — good news
- **WHMCS ≥ 5.3 client passwords are bcrypt** (`password_hash()`, `$2y$…`) — **directly
  compatible with Laravel's `Hash::check()`**. Copy `tblusers.password` (WHMCS 8) /
  `tblclients.password` (older) into `client_users.password` → clients keep their logins.
- Edge case: pre-5.3 legacy `md5:salt` hashes for users who never logged in since
  upgrading → force reset or OTP re-registration (portal already supports OTP signup).
- Respect the WHMCS-8 **user↔clients pivot**: one login may access several clients;
  `client_users` is per-client, so a shared login becomes one `client_users` row per client.

### 6.5 ETL approach (recommended)
1. **Direct read-only MySQL** access to WHMCS (GRANT SELECT; snapshot or replica) for
   bulk ETL — complete, fast, gets password hashes (the API never exposes them).
2. **Small WHMCS API script** only for `DecryptPassword` (service passwords / encrypted
   custom fields) — don't reimplement WHMCS crypto (`$cc_encryption_hash` KDF varies by version).
3. Build `php artisan whmcs:import {--tenant=} {--dry-run}` — staged, idempotent
   (keyed on new `legacy_id` columns), per-entity order:
   servers → products → clients → client_users → subscriptions+hosting_accounts →
   invoices+items → payments → (domains, custom fields → metadata).
4. **Rehearse on staging** with reconciliation: row counts, per-client invoice totals,
   sum(payments) vs paid invoices, credit balances.
5. **Freeze WHMCS at cutover** (disable its cron — no invoice generation/suspensions),
   run final delta import, then switch off.

### 6.6 Import gotchas (from schema research)
- **`nextduedate` vs `nextinvoicedate`** diverge; migrate **`nextduedate`** as the
  paid-through anchor and let `RecurringInvoiceService` compute its own 30-day window —
  copying both double-invoices or skips a cycle at cutover.
- **Credit accounting:** collected = `tblinvoices.total − tblinvoices.credit`; exclude
  `AddFunds` invoices from revenue (they're top-ups) or you double-count.
- **Recurring promos:** `tblhosting.amount` may be *pre-discount* (promo applied as
  negative `PromoHosting` invoice lines) — cross-check each service's last renewal
  invoice total or discounted customers get silent price hikes.
- **Uniqueness:** MoBilling enforces unique `(tenant_id, email)` and `(tenant_id, phone)`
  on clients; WHMCS doesn't — dedupe/merge strategy needed before insert.
- **Amounts are in the client's currency**; MoBilling is single-currency per tenant —
  if all WHMCS clients share one currency this is a non-issue; otherwise convert with
  `tblaccounts.rate` and record originals in metadata.
- `tblinvoiceitems.relid` may point at deleted rows (no FKs) — tolerate orphans.
- Don't migrate card PANs. Gateway tokens (`tblpaymethods`, `tblhosting.subscriptionid`)
  are useless without the same gateway relationship — customers re-establish payment
  via the Pesapal pay page (or a future tokenizing gateway).

---

## 7. Security

- `servers.api_token` with Laravel **encrypted** cast; never sent to the frontend.
- **Reseller** WHM token where possible; IP-allowlist the WHM API at the firewall.
- No cPanel passwords stored — SSO (`create_user_session`) + `passwd` resets.
- New `hosting.*` permissions gate all provisioning actions; everything audited in
  `provisioning_logs` (and `CommunicationLog` already covers client messaging).
- WHMCS DB credentials for the importer: read-only user, dropped after cutover.

---

## 8. Phased roadmap

### Phase 0 — Foundations (safe, read-only)
- [ ] `servers` table + model + Settings CRUD + "Test connection" (`listpkgs`)
- [ ] `WhmService` read-only calls (`listpkgs`, `accountsummary`) against a real box
- [ ] Add `legacy_id` columns (clients, product_services, client_subscriptions, documents, payments_in)
- [ ] Add client `status`/`notes` columns (WHMCS parity)

### Phase 1 — Provisioning MVP
- [ ] Product provisioning fields; `hosting_accounts` + `provisioning_logs`
- [ ] `ClientSubscription` observer → queued jobs → `createacct` / `suspendacct` / `unsuspendacct` / `removeacct`
- [ ] Welcome email on provision; `hosting:reconcile` daily
- [ ] Admin hosting panel + client-portal "My Hosting" + **cPanel SSO**

### Phase 2 — WHMCS importer
- [ ] `whmcs:import` command (staged order per §6.5, `--dry-run`, idempotent)
- [ ] Status/cycle mappers per §6.2 (+ `SELECT DISTINCT` verification against live DB)
- [ ] Portal password carry-over (bcrypt) + OTP fallback
- [ ] Reconciliation report (counts, totals, credit)
- [ ] Staging rehearsal ×2

### Phase 3 — Parity extras (as needed)
- [ ] `changepackage` upgrades, password reset UI, usage display
- [ ] Client credit/wallet (if WHMCS credit balances are material)
- [ ] Domain registrar integration (if we sell domains)
- [ ] Support tickets or external helpdesk decision
- [ ] Setup fees / per-cycle pricing / biennial cycles if catalog needs them

### Cutover
- [ ] Freeze WHMCS cron → final delta import → reconcile
- [ ] Point clients at the MoBilling portal (logins carry over)
- [ ] Run both read-only in parallel ~2 weeks → decommission WHMCS

---

## 9. Open questions (decide before Phase 2)

1. **Domains:** do we sell/renew domains via WHMCS? (Registrar integration in scope or not.)
2. **Support tickets:** build in MoBilling, or adopt an external helpdesk at cutover?
3. **Credit balances:** how much client credit is outstanding in WHMCS? (Determines whether the wallet feature is required or refundable/ignorable.)
4. **Catalog shape:** any WHMCS products with setup fees, per-cycle price differences, biennial/triennial cycles, addons, or config options? (Determines schema extensions vs workarounds.)
5. **Ordering:** staff-created subscriptions only (current model), or client self-order later?
6. **Terminate policy:** on cancellation — immediate `removeacct`, or suspend-then-terminate after N days?
7. **Servers:** how many WHM boxes; root or reseller tokens?

---

## Appendix — repo reference map

| Concern | File |
|---|---|
| HTTP-service pattern to copy | `app/Services/WhatsAppService.php` |
| Activation trigger | `app/Http/Controllers/PaymentInController.php` (`activateLinkedSubscriptions`) |
| Suspend trigger | `app/Console/Commands/SuspendUnpaidSubscriptions.php` |
| Manual cancel path (only cancel path today) | `app/Http/Controllers/ClientSubscriptionController.php` (`update`) |
| ⚠ NOT a client-subscription command (tenant SaaS billing) | `app/Console/Commands/ExpireSubscriptions.php` |
| Recurring billing + reminders | `app/Services/RecurringInvoiceService.php` |
| Dunning / late fees | `app/Console/Commands/ProcessOverdueInvoices.php` |
| Subscription model | `app/Models/ClientSubscription.php` |
| Product model | `app/Models/ProductService.php` |
| Client + portal user models | `app/Models/Client.php`, `app/Models/ClientUser.php` |
| Client portal routes | `routes/api.php` (~L546-591, `/portal`) |
| Public pay page | `app/Http/Controllers/InvoicePaymentController.php` (`/pay/{document}`) |
| Tenant gateway | `app/Services/TenantPesapalService.php`, `TenantPesapalWebhookController` |
| Scheduler | `routes/console.php` |
| Audit-log precedent | `CronLog`, `CommunicationLog`, `provisioning_logs` (new) |
