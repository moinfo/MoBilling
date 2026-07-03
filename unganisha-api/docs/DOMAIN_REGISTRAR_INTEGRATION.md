# Domain Registrar Integration (TCRA / TZNIC .tz via FRED-EPP) — Multi-Tenant

> Goal: sell, register, renew, and manage **.tz domains** natively in MoBilling —
> multi-tenant like everything else — by integrating with the **.tz registry**
> (operated under **TCRA**; registry endpoints run **TZNIC/FRED**), and reusing the
> **already-built registrar portal at `/var/www/html/fred-client`** instead of
> rebuilding EPP from scratch.
>
> Companion to `WHM_CPANEL_INTEGRATION.md` (the WHMCS exit plan): this closes the
> "domains" gap listed there, giving WHMCS `tbldomains` a real landing place.

---

## 1. Background: how .tz registration actually works

- **TCRA** (Tanzania Communications Regulatory Authority) oversees the `.tz` ccTLD;
  the registry platform is the **FRED** registry system (CZ.NIC software) at
  **TZNIC** endpoints (`*.tznic.or.tz`).
- Accredited registrars talk to FRED over **EPP** (Extensible Provisioning Protocol):
  TLS on **port 700** with a **client certificate** + registrar ID/password.
- FRED's EPP dialect manages four object types:
  - **contact** (registrant/admin/tech handles)
  - **domain** (the registration itself; links contacts + nsset + keyset)
  - **nsset** (a named set of nameservers — FRED-specific, unlike generic EPP)
  - **keyset** (DNSSEC keys — FRED-specific)
- Core EPP operations: `check`, `info`, `create`, `renew`, `transfer` (with auth-info
  code), `update`, `delete`, plus registrar **credit** queries (registrations draw
  down a prepaid registrar balance at the registry).

> Note for gTLDs (.com/.net/…): those go to different registrars/registries
> (ResellerClub, Namecheap API, etc.) — out of scope here, but the design below uses a
> **driver abstraction** so a gTLD driver can be added later without rework.

---

## 2. What we already have: the `/var/www/html/fred-client` portal (audited)

A custom, **near-complete ".tz registrar portal"** ("Moinfotech Domains Portal") —
substantially built, deployment-staged:

| Component | Stack | State |
|---|---|---|
| Backend | **Django 6 + DRF**, Python 3.12, `epplib` (cisagov) EPP client with a threaded connection pool | Full EPP service layer: check/create/renew/transfer/info/delete for domains, contacts, nssets, keysets + registrar credit |
| REST API | `/api/domains/check|register|transfer`, `/api/domains/{name}/renew|info`, DNS nsset CRUD, keyset/DNSSEC CRUD, `/api/billing/credit/` | Working per README; Celery+Redis for async work |
| Frontend | Next.js 16 + Mantine | Customer-facing portal UI |
| Billing | Own Pesapal integration (buy-a-domain flow) | Hardened |
| WHMCS module | `whmcs/modules/registrars/fred/` (PHP) | **Obsolete once we exit WHMCS** — superseded by this plan |

**Live configuration** (secrets redacted; in `backend/.env`):
- `EPP_HOST=mtanzania.tznic.or.tz`, `EPP_PORT=700` — real TZNIC endpoint
- `EPP_REGISTRAR_ID=REG-MOINFOTECH` — our registrar accreditation
- Client cert/key installed: `/etc/ssl/fred/client.pem` + `client-key.pem` (mode 600)
- FRED schema namespaces: `contact-1.6, domain-1.4, nsset-1.2, keyset-1.3`

**Gaps found in the audit** (to fix during integration):
- ⚠ `verify=False` on the EPP TLS transport (`backend/apps/registry/epp_client.py`
  line ~74) — server certificate not verified. Pin/verify the TZNIC CA.
- The `sync_*` / `seed_pricing` management commands referenced in the README aren't in
  the tree — bulk registry sync may be partial/uncommitted.
- No cron automation and no logs yet — renewals/sync are not running automatically.
- MoBilling (`unganisha-api`) currently has **zero** connection to any of this
  (grep-verified: no fred/epp/tcra/tznic references).

---

## 3. Architecture decision: reuse, don't rebuild

Three options considered:

| Option | Description | Verdict |
|---|---|---|
| **A. Registrar microservice (RECOMMENDED)** | Keep the Django backend as a headless **EPP/registrar service**; MoBilling calls its REST API through a Laravel driver. Retire/absorb its own billing + frontend over time (MoBilling owns billing). | ✅ EPP layer (the hard, fiddly part: FRED schemas, TLS, connection pooling) is already built and near-live. Fastest path, lowest risk. |
| B. Reimplement EPP in Laravel/PHP | Port epplib behavior into a PHP EPP client inside unganisha-api | ❌ Weeks of rework duplicating working code; PHP EPP libraries for FRED dialect are weak |
| C. Keep two separate products | fred-client portal stays standalone; link out from MoBilling | ❌ Two billing systems, two client logins — exactly the fragmentation we're leaving WHMCS to escape |

**Decision: Option A.** MoBilling becomes the **billing + tenant + client-portal brain**;
fred-client's Django backend becomes the **registrar execution arm** (internal service,
not directly internet-facing). Its Next.js frontend and Pesapal billing become
redundant for MoBilling tenants (keep them only if `moinfo.tz` should continue as a
separate direct-retail storefront — see Open Questions).

```
MoBilling (Laravel, multi-tenant)                    fred-client backend (Django)
┌──────────────────────────────────┐   internal      ┌──────────────────────────┐
│ domains UI (staff + client portal)│   HTTP + auth   │ REST API                 │
│ DomainRegistrarManager            │ ──────────────► │ EPPService (epplib pool) │──EPP/700──► TZNIC FRED
│  └ FredHttpDriver                 │                 │ contacts/nsset/keyset    │            (.tz registry)
│  └ (future) ResellerClubDriver    │                 └──────────────────────────┘
│ domains, registrar_accounts tables│
│ billing: invoices→pay→register    │
└──────────────────────────────────┘
```

---

## 4. Multi-tenancy model (the key design point)

An EPP registrar account (registrar ID + client cert + prepaid registry credit) is
**one accreditation** — most MoBilling tenants will NOT have their own. So support
both modes, consistent with how the rest of MoBilling does per-tenant config
(`Tenant.pesapal_*`, `Tenant.whatsapp_*`):

1. **Platform-registrar mode (default):** all tenants register through the platform's
   accreditation (`REG-MOINFOTECH`). The platform sets **base cost**; each tenant sets
   their **retail price** per TLD. Registry credit is the platform's; tenant pays the
   platform (already modeled by existing tenant SaaS billing patterns).
2. **Tenant-registrar mode:** a tenant who holds their own TZNIC accreditation stores
   their own registrar ID/password/cert reference, and their domains run over their
   own EPP session and registry credit.

Every domain row is tenant-scoped with `BelongsToTenant` exactly like the rest of the
app; the registrar account used is resolved per tenant with platform fallback.

---

## 5. Data model (new tables in unganisha-api)

### `registrar_accounts`
| column | notes |
|---|---|
| id, tenant_id **nullable** | `NULL tenant_id` = the platform account (fallback for all tenants) |
| name, driver | driver: `fred_epp` (future: `resellerclub`, …) |
| endpoint_url | the Django service base URL (or registrar API URL for other drivers) |
| registrar_id | e.g. `REG-MOINFOTECH` |
| credentials | **encrypted cast** json (EPP password / service auth token) |
| cert_path, key_path | filesystem refs (never in DB content) |
| is_active, is_sandbox | |

### `domain_tlds` (pricing catalog)
| column | notes |
|---|---|
| id, tenant_id nullable | platform row = base cost; tenant row = retail override |
| tld | `.co.tz`, `.tz`, `.or.tz`, `.ac.tz`, … |
| register_price, renew_price, transfer_price | per year |
| years_min/max, is_active | |

### `domains`
| column | notes |
|---|---|
| id, tenant_id, client_id | tenant-scoped like every model (BelongsToTenant) |
| registrar_account_id | which accreditation registered it |
| name | `example.co.tz` (unique per registry — global unique index) |
| status | `pending / active / expired / transferred_out / cancelled / failed` (+ keep raw registry status in meta) |
| registrant_contact_handle, admin/tech handles | FRED contact handles |
| nsset_handle, keyset_handle | FRED objects (DNSSEC via keyset) |
| registered_at, **expires_at** | registry is authoritative — synced, not computed |
| auto_renew bool | drives renewal invoicing |
| client_subscription_id nullable | optional link if sold as part of a bundle |
| epp_auth_info | encrypted (transfer code) |
| meta json, legacy_id | `legacy_id` ← WHMCS `tbldomains.id` for the migration |

### `domain_logs`
Append-only audit of every registrar call (mirrors `provisioning_logs` /
`cron_logs` pattern): domain_id, action, request (sanitized), response, status, error.

---

## 6. Service layer (unganisha-api)

Follow the existing service pattern (`WhatsAppService`, `TenantPesapalService`,
planned `WhmService`):

```php
interface RegistrarDriver {
    public function check(string $domain): DomainAvailability;
    public function register(DomainOrder $o): DomainResult;   // contacts+nsset+domain create
    public function renew(string $domain, int $years): DomainResult;
    public function transferIn(string $domain, string $authInfo): DomainResult;
    public function info(string $domain): DomainInfo;          // authoritative expiry/status
    public function updateNameservers(string $domain, array $ns): DomainResult;
    public function setDnssec(string $domain, array $keys): DomainResult;
    public function credit(): ?Money;                          // registry balance
}

class FredHttpDriver implements RegistrarDriver { /* calls the Django REST API */ }

class DomainRegistrarManager {
    // resolves the tenant's registrar_account (fallback: platform account),
    // instantiates the driver, writes domain_logs, dispatches queued jobs
}
```

- All registrar calls run as **queued jobs** (EPP/registry can be slow) — same rule as
  WHM provisioning.
- The Django service gets a simple **service-to-service auth** (token header) and is
  bound to localhost / private network only.

---

## 7. Billing & lifecycle wiring (reuses what's already proven)

| Event | Flow |
|---|---|
| **Order / register** | Staff (or portal client) picks domain + years → availability `check` → invoice created (`Document`, price from `domain_tlds`) → **on payment** (`PaymentInController` — same hook that activates subscriptions) → queued `RegisterDomainJob` → EPP create → domain `active`, `expires_at` synced → confirmation email |
| **Renewal invoicing** | New daily command `domains:process-renewals` (register in `routes/console.php` beside the others): for `auto_renew` domains expiring within N days (default 45/30) → generate renewal invoice → existing reminder ladder (21/14/7/3/1) applies |
| **On renewal payment** | queued `RenewDomainJob` → EPP renew → re-sync `expires_at` |
| **Non-payment** | do **nothing destructive** — domain simply expires at the registry (registry grace/redemption applies); status flips on sync. Never EPP-delete for non-payment. |
| **Transfer in** | client provides auth-info code → invoice (if priced) → `TransferDomainJob` |
| **Nightly sync** | `domains:sync` — `info` every active domain (batched), reconcile status/expiry drift, refresh registrar credit, alert on low platform credit |

Notifications reuse the existing stack (mail/SMS/WhatsApp channels + tenant-editable
templates): add `DomainRegisteredNotification`, `DomainRenewalReminder`,
`DomainExpiredNotification`.

## 8. UI

**Staff (MoBilling admin)**
- Domains menu: searchable tenant-scoped list (name, client, expiry, auto-renew, status).
- Register/transfer wizard (availability check → contact selection → invoice).
- Domain detail: nameservers, DNSSEC, transfer code reveal (permission-gated), renewal
  history, `domain_logs` viewer.
- Settings → Registrar Accounts (platform + tenant mode, "Test connection" = credit query).
- Settings → TLD Pricing (platform base + tenant retail).
- New permissions: `domains.read/create/renew/transfer/manage_dns/settings`.

**Client portal** (extends the existing `/portal`)
- "My Domains": list + expiry, pay-renewal via the existing public pay page flow,
  nameserver self-service (optional, per-tenant toggle).

---

## 9. Security

- Fix `verify=False` in `epp_client.py` — verify TZNIC's CA chain (or pin it).
- Registrar credentials: **encrypted casts**; certs on disk (0600, outside webroot,
  never in git — history already had one commit/revert incident; keep it that way).
- Django service: not internet-exposed; token auth from Laravel only; rate-limited.
- `epp_auth_info` (transfer codes) encrypted; reveal permission-gated + audited.
- Registry credit is money — alert (mail + WhatsApp) when platform credit drops below
  a threshold, and log every debit-causing call in `domain_logs`.

---

## 10. WHMCS migration tie-in (`tbldomains`)

From the WHMCS exit plan (`WHM_CPANEL_INTEGRATION.md` §6): import `tbldomains` →
`domains`:

| WHMCS | MoBilling |
|---|---|
| `domain`, `userid` | `name`, `client_id` (via legacy map) |
| `registrationdate`, `expirydate` | `registered_at`, `expires_at` (then trust `domains:sync`) |
| `nextduedate`, `recurringamount` | renewal invoicing anchor + tenant retail price sanity-check |
| `status` (Active/Expired/Cancelled/Pending Transfer/…) | mapped status; raw kept in `meta.whmcs_status` |
| `donotrenew` | `auto_renew = !donotrenew` |
| registrar module = `fred`-based | registrar_account = platform account — **no registry-side change needed**: the domains already live under REG-MOINFOTECH, so the "transfer" is purely database-side |

The fred-client **WHMCS module is retired** at cutover.

---

## 11. Phased roadmap

### Phase 0 — Foundations
- [ ] Fix EPP TLS verification in fred-client; add service-token auth to the Django API; bind to private interface
- [ ] `registrar_accounts`, `domain_tlds`, `domains`, `domain_logs` migrations + models
- [ ] `FredHttpDriver` + `DomainRegistrarManager` with read-only ops (`check`, `info`, `credit`) + Settings "Test connection"

### Phase 1 — Core lifecycle (MVP)
- [ ] Register + renew jobs wired to invoice payment (same hook as subscription activation)
- [ ] `domains:process-renewals` + `domains:sync` scheduled commands + notifications
- [ ] Staff Domains UI (list, wizard, detail, logs) + permissions
- [ ] TLD pricing (platform base + tenant retail)

### Phase 2 — Full management
- [ ] Transfers (in/out with auth-info), nameserver + DNSSEC management via driver
- [ ] Client-portal "My Domains" + renewal payment
- [ ] WHMCS `tbldomains` import (extends `whmcs:import`)
- [ ] Low-credit alerts; contact-handle management UI

### Phase 3 — Consolidation / growth
- [ ] Decide fate of fred-client's Next.js storefront + its own Pesapal billing (retire, or keep as direct-retail funnel feeding MoBilling)
- [ ] gTLD driver (ResellerClub/Namecheap) if we sell .com/.net
- [ ] Tenant-registrar mode onboarding flow (own accreditation)

---

## 12. Open questions

1. **moinfo.tz storefront:** keep fred-client's own frontend+billing as a public
   direct-retail portal, or retire it and make MoBilling the only face?
2. **Registry credit ownership** in platform mode: prepay model / tenant markup rules?
3. **Which .tz second-levels** do we sell (`.co.tz`, `.or.tz`, `.ac.tz`, `.tz` direct…)
   and at what base/retail prices?
4. **Contact handles:** one registrant handle per client (auto-created from Client
   record) or per-domain custom contacts?
5. **Is `mtanzania.tznic.or.tz` the production or OT&E node?** Confirm with
   TZNIC/TCRA before go-live; keep `is_sandbox` accurate.
6. Do any WHMCS domains use a **non-FRED registrar module** (gTLDs)? They'd need a
   different driver or manual handling at import.

---

## Appendix — reference map

| Concern | Location |
|---|---|
| Existing EPP service (reuse) | `/var/www/html/fred-client/backend/apps/registry/epp_client.py` |
| Existing domain REST API | `/var/www/html/fred-client/backend/apps/{domains,dns,contacts,keysets,billing}` |
| EPP config (host, registrar id, cert paths) | `/var/www/html/fred-client/backend/.env` |
| Client certs | `/etc/ssl/fred/client.pem`, `/etc/ssl/fred/client-key.pem` |
| Obsolete-at-cutover WHMCS module | `/var/www/html/fred-client/whmcs/modules/registrars/fred/` |
| Laravel service pattern to copy | `unganisha-api/app/Services/{WhatsAppService,TenantPesapalService}.php` |
| Payment→activation hook to extend | `unganisha-api/app/Http/Controllers/PaymentInController.php` |
| Scheduler to extend | `unganisha-api/routes/console.php` |
| WHMCS exit plan (companion doc) | `unganisha-api/docs/WHM_CPANEL_INTEGRATION.md` |
