# WHMCS Parallel Operation & Final Cutover Runbook

> **STATUS (2026-07-03): PARALLEL MODE — WHMCS is still the primary billing
> system for its clients.** MoBilling has all the data and all the machinery,
> but its automations deliberately skip WHMCS-imported records
> (`WHMCS_PARALLEL_MODE=true`). This document is the memory of how we got here
> and the exact runbook for the final cutover, executed when the business says
> "complete the migration" and provides a **fresh WHMCS database dump**.

---

## 1. What has been built and done (chronicle)

| Date | Milestone |
|---|---|
| 2026-07-03 | WHMCS DB (168MB dump, taken **2026-07-03 06:31**) imported locally as MySQL `moinfote_billing`; read-only `whmcs` connection configured |
| 2026-07-03 | `whmcs:import` executed into tenant **Moinfotech Company Limited** (`019c8f39-679e-70d2-af92-ac72a25b0d9c`): 206 clients (70 merged into existing MoBilling clients by email/phone), 202 portal logins (bcrypt carried — old passwords work), 172 subscriptions, 1,052 invoices (`WHMCS-{id}` numbering; original number in notes), 497 payments, 192 domains |
| 2026-07-03 | WHM provisioning live: server `ice.superdnssite.com` (reseller `moinfote`, API token), 39 hosting products mapped to real WHM packages, **109 cPanel accounts adopted & verified** (37 WHMCS phantoms removed — those sites are hosted directly on the MoBilling server), auto-provision ON |
| 2026-07-03 | Domain registry live: fred-client Django service hardened (pinned Rajisi-CA TLS, `mobilling-service` token), 147/188 domains registry-synced (11 gTLDs unmanaged, 30 registry-purged closed), TLD pricing seeded (13 zones), payment-gated register/renew jobs |
| 2026-07-03 | **De-duplication of the parallel-run overlap**: 63 duplicate imported subscriptions cancelled (native twin kept; hosting accounts relinked), 75 domains set `auto_renew=false` (billed via native 20,000/yr subs), 362 `RecurringInvoiceLog` rows seeded from WHMCS's own invoice history, 2 duplicate unpaid invoices cancelled (`WHMCS-1281`, `WHMCS-1291`), 4 unpaid WHMCS domain invoices wired to registry fulfilment |
| 2026-07-03 | Business decision: **keep operating in WHMCS until feature-complete** → `WHMCS_PARALLEL_MODE` introduced and enabled |

Companion docs: `WHM_CPANEL_INTEGRATION.md` (design), `DOMAIN_REGISTRAR_INTEGRATION.md`
(design), `IMPLEMENTATION_PLAN.md` (build checklist). Import reports:
`storage/app/whmcs-import-report-*.json`.

---

## 2. Parallel mode — who does what right now

`config/whmcs.php` → `parallel_mode` (env `WHMCS_PARALLEL_MODE`, currently **true**).

While true, MoBilling automations **skip every record with a `legacy_id`**:

| Automation | Behavior in parallel mode |
|---|---|
| `invoices:process-recurring` (07:00) | Skips imported subscriptions (WHMCS generates their renewal invoices); reminders skip imported invoices |
| `invoices:process-overdue` (08:30) | No late fees / dunning on imported invoices (WHMCS duns its own) |
| `subscriptions:suspend-unpaid` (09:30) | Never suspends imported subscriptions |
| `domains:process-renewals` (06:30) | Skips imported domains (WHMCS invoices those renewals) |
| `domains:sync` (05:45) | **Still runs for everything** — read-only registry truth, safe |
| `hosting:reconcile` (05:30) | **Still runs** — read-only against WHM, safe |

Native MoBilling records (no `legacy_id`) are billed/dunned exactly as before.

**Rules for staff during the parallel period:**
- Operate imported clients (billing, payments, suspensions, new orders) **in WHMCS**.
- MoBilling remains read-usable for those clients (profiles, history, hosting
  panel with SSO, domains view) — just don't record their payments here, or
  the two systems diverge.
- Anything WHMCS does after **2026-07-03 06:31** is NOT in MoBilling until the
  final delta import.
- New WHM API activity note: both systems can suspend/unsuspend accounts;
  `hosting:reconcile` follows the server's truth nightly either way.

---

## 3. FINAL CUTOVER RUNBOOK

Trigger: business says "complete the migration" and provides a **fresh WHMCS
dump**. Expected effort: one session, ~1–2 hours, best done early morning
before the 05:30 cron train.

### Step 0 — Freeze WHMCS
- [ ] Disable the WHMCS cron (cPanel → Cron Jobs → the `crons/cron.php` line)
      **and** stop taking payments/orders in WHMCS.
- [ ] Take the final dump AFTER the freeze: full export of the WHMCS database.

### Step 1 — Load the fresh dump
```bash
scp moinfote_billing.sql root@50.116.44.162:/tmp/
mysql moinfote_billing < /tmp/moinfote_billing.sql   # replaces the local copy in place
```

### Step 2 — Delta import (idempotent — safe to re-run)
```bash
cd /var/www/html/MoBilling/unganisha-api
php artisan whmcs:import --tenant=019c8f39-679e-70d2-af92-ac72a25b0d9c --dry-run   # review counts first
php artisan whmcs:import --tenant=019c8f39-679e-70d2-af92-ac72a25b0d9c
```
Everything keys on `legacy_id`, so only new/changed rows land. Review the
report file it prints.

### Step 3 — Re-run the de-duplication + history seeding
The same five fixes as 2026-07-03 (new WHMCS activity since then may have
created new invoices/services). Ask Claude to "re-run the whmcs dedup pass" —
the logic is: (1) cancel imported subs duplicating native ones (label match,
then unambiguous price+expiry match; cancel **quietly**, relink hosting
accounts); (2) `auto_renew=false` on domains billed by native domain subs;
(3) seed `RecurringInvoiceLog` from WHMCS `tblinvoiceitems` (type=Hosting);
(3b) wire unpaid WHMCS domain invoices to registry fulfilment
(`meta.pending_action=renew` + `renewal_document_id`); (4) cancel unpaid
imported invoices with a native unpaid twin (same client/amount/±14d due).

### Step 4 — Flip the switch
```bash
# in unganisha-api/.env
WHMCS_PARALLEL_MODE=false
php artisan config:clear
```

### Step 5 — Verify before the next cron train
- [ ] Simulate 07:00: replicate `processUpcomingBills` (walk start_date by
      cycle; ≤ today+30; no RecurringInvoiceLog row) → the would-invoice list
      must contain **no duplicates** of WHMCS-issued invoices.
- [ ] Simulate 06:30: active auto-renew domains ≤45d without open invoices —
      list must be sensible.
- [ ] Check 08:30 dunning targets: imported unpaid invoices WILL now be dunned
      — confirm the list is intended.
- [ ] `php artisan domains:sync` + `php artisan hosting:reconcile` — clean.

### Step 6 — Client-facing switch
- [ ] Point clients at the MoBilling portal (logins carried over; OTP
      re-registration as fallback).
- [ ] Update payment links/templates that referenced WHMCS.
- [ ] WHMCS → read-only for a 2-week reference window, then decommission;
      archive a final dump; drop the local `moinfote_billing` DB afterwards.

### Step 7 — Post-cutover watchlist
- [ ] TZNIC registry credit topped up for every selling zone (renewals draw
      real prepaid credit; nightly low-credit watch warns under 50k/zone).
- [ ] Registry contact for `mobilling-service` (needed for NEW .tz
      registrations; renewals work without it).
- [ ] The ~11 **gTLD** domains (.com/.net/.org, `meta.unmanaged`) — renew
      manually at their actual registrar, or build a gTLD driver
      (ResellerClub/Namecheap) — see `DOMAIN_REGISTRAR_INTEGRATION.md` §Phase 3.
- [ ] fred-client WHMCS module (`fred-client/whmcs/`) is retired — tell whoever
      maintains it.

---

## 4. Known gaps vs WHMCS (why we're still parallel)

Tracked in `WHM_CPANEL_INTEGRATION.md` §3; the notable ones:
~~support tickets~~ (BUILT 2026-07-03: full helpdesk, staff + portal),
~~client self-service domain ordering~~ (BUILT 2026-07-03: portal register/
transfer/renew), ~~client self-service hosting ordering~~ (BUILT 2026-07-03:
Shopping Cart catalog -> order -> pay -> auto-provision), gTLD registrar
driver, announcements/news module,
promo codes / proration / client credit wallet, WHMCS addon-module features.
Completing these (or accepting their absence) is the trigger for cutover.
