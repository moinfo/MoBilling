# MoBilling — Complete System & Pricing Documentation

**Prepared for:** marketing, sales and social-media content production
**Product owner:** Moinfotech Company Limited — Njuweni Hotel, 1st Floor, Room 134, Kibaha, Tanzania
**Source:** generated directly from the live codebase and the production database (not from a brochure)
**Date:** 2 September 2026 — **revised against the newly loaded production database**

> **What changed in this revision:** self-hosted licence prices are now set and sellable; Moinfotech has its own retail domain pricing that overrides the platform defaults (and .tz transfers are free); `.com`/`.net`/`.org` turn out to be manual-fulfilment, not automatic; Broadcast now supports WhatsApp with per-recipient failure tracking and retry; and the system now carries real production load — 6 businesses, 286 clients, 1,356 documents, 551 subscriptions.

---

## 1. What MoBilling actually is

MoBilling is a **full business-operations platform** for African small and medium businesses — most directly a **WHMCS alternative** for hosting and domain resellers, but far wider than that. One login covers billing, the client portal, domains, hosting automation, support, HR/payroll, statutory compliance, field sales and marketing operations.

It is not "an invoicing app". The system currently ships:

| Metric | Count |
|---|---|
| Backend API controllers | 133 |
| Database tables (migrations) | 274 |
| Eloquent models | 120+ |
| Granular permissions | 250+ (51 menu-level, 200+ action-level) |
| Staff-side screens | 90+ |
| Client-portal screens | 22 |
| Standard reports | 13 |
| Automated daily jobs | 20 |
| Client-portal API endpoints | ~56 |

### Technology (for credibility posts, not for selling)

| Layer | Technology |
|---|---|
| Backend | Laravel 12 (PHP 8.2+), MySQL 8 |
| Web app | React 19 + Vite + Mantine UI v8 |
| Mobile | Flutter (staff app in build; client app planned) |
| Auth | Laravel Sanctum tokens + optional 2FA + idle timeout |
| Payments | Pesapal (M-Pesa, cards, mobile money), bank, cash, cheque |
| Domains | EPP / FRED protocol direct to the TCRA–tzNIC registry |
| Hosting | WHM / cPanel API |
| Messaging | SMS gateway, WhatsApp via MoSMS, SMTP e-mail, Firebase push |
| PDF | DomPDF (invoices, receipts, payslips, reports) |

---

## 2. The four ways MoBilling is sold

This matters for content — each has a different audience and a different price list.

1. **MoBilling Cloud (hosted SaaS)** — a business signs up at mobilling.co.tz, gets a 7-day free trial, then pays a monthly subscription. Section 9.1.
2. **MoBilling Self-Hosted (licensed)** — a customer installs MoBilling on their own server with a licence key. Three product lines: Lite, Reseller and Complete, from **TZS 10,000/month or 80,000/year**. Now fully priced and sellable online. Section 9.2.
3. **White-label reseller** — a tenant runs the whole platform under **their own brand and domain**, sets their own hosting and per-TLD prices, and keeps the margin. Moinfotech runs the registry connections and infrastructure behind the scenes.
4. **Moinfotech's own services** sold *through* MoBilling — web hosting, business e-mail, domains, reseller plans, website design, SMS. Section 9.5.

---

## 3. Module catalogue — staff/admin application

Grouped exactly as the product's sidebar groups them.

### 3.1 Dashboard

A permission-aware command centre. Every tile is individually permission-gated (28 separate dashboard permissions), so a field officer, an accountant and a director all open the same page and see three different dashboards.

Available tiles: total receivable, total received, outstanding, overdue invoices, overdue bills, upcoming bills, due-soon and urgent statutory obligations, revenue chart, invoice-status chart, payment-method chart, bank-account breakdown, system-records breakdown, top clients, recent invoices, subscription stats, upcoming renewals, domains, hosting, tickets, expenses, WhatsApp contacts, field visits, SMS balance, activity calendar, my attendance, my report deductions, my total deductions, month filter.

> **Content angle:** "Your dashboard shows only what your job needs — not everyone's salary data."

---

### 3.2 Billing (the core)

| Sub-module | What it does |
|---|---|
| **Collection** | A daily call-plan dashboard: total outstanding banner, aging breakdown, today's due invoices, overdue list, and an invoice preview drawer so the collector can call with the numbers in front of them. |
| **Follow-ups** | Log every collection call: outcome (promised / paid / no answer), promise date, promise amount, next follow-up date. Promise fulfilment is then measured in the Collection Effectiveness report. |
| **Clients** | Full client directory with structured addresses, tax IDs, multiple contacts, credit wallet, per-client statement and history. Includes a client-merge tool for duplicates. |
| **Portal Users** | Create and manage the login accounts your clients use in the portal — including issuing portal passwords and portal login on behalf of a client. |
| **Add Order** | Staff-side version of the shopping cart: place an order for a client, pick a domain, apply a coupon, generate the invoice. |
| **Products & Services** | The catalogue: products vs services, price, tax %, unit, category, billing cycle (once / monthly / quarterly / half-yearly / yearly), and — for hosting items — provisioning type, target server, cPanel package and auto-provision toggle. `portal_visible` controls what clients can order themselves. |
| **Product Add-ons** | Optional extras attached to a product (extra storage, extra mailboxes, backups) with their own price and billing cycle. |
| **Configurable Options** | WHMCS-style option groups and choices — e.g. "Disk space: 5 GB / 10 GB / 50 GB", each choice carrying its own price delta. |
| **Promotions / Coupons** | Percentage or fixed-value coupons, scoped by what they apply to, with max-uses, minimum order value, start/expiry dates, and a `recurring` flag that decides whether the discount applies to renewals too. Redemptions are logged. |
| **Quotations** | Professional quotes that convert to proforma or invoice in one click. |
| **Proforma Invoices** | Pre-invoice documents for clients who need them for procurement or payment approval. |
| **Invoices** | Automatic numbering, tax, due dates, approval workflow, PDF download, e-mail send/resend, due-date extension, cancellation requests. |
| **Unpaid Invoices** | A dedicated worklist of everything still open. |
| **Credit Notes** | Formal credit documents against issued invoices. |
| **Payments (in)** | Record and reconcile receipts: M-Pesa, Pesapal, bank transfer, cash, cheque. Receipts are generated as PDF and can be resent. Refunds are tracked separately. |
| **Client Subscriptions** | Recurring services per client: label, quantity, discount, start/expiry, status, first-payment vs recurring amount, payment method, promo code. This is what drives renewals. |
| **Next Bills** | The forward renewal schedule — what will be invoiced, to whom, and when. |
| **Client credit wallet** | Clients hold a prepaid balance; invoices can be settled from it and auto-renewals draw from it automatically. |

> **Content angles:** "From quote to invoice to receipt in three clicks." · "Your renewals invoice themselves." · "Every collection call, logged — and every promise, measured."

---

### 3.3 Web Services — domains & hosting (the WHMCS-replacement core)

**Domains**
- Live availability search against the registry, including a **public search box** you can embed on your website.
- Register, renew and transfer **.tz domains directly at the TCRA/tzNIC registry over EPP** (FRED driver) — not through a middleman.
- gTLDs (.com, .net, .org) are **sold and billed but fulfilled by hand** — they are flagged `is_unmanaged` because no registrar driver exists for them. The availability check skips the registry, the paid order lands in an explicit "Awaiting Registration" state, and staff record the real registration and expiry dates once they have registered it at their own outside registrar. This is a deliberate design, not a gap — but it is not automatic.
- Per-TLD pricing you set yourself: register / renew / transfer / reseller price, min and max years.
- Registrant, admin, nsset and keyset handles; EPP auth codes (encrypted at rest, hidden from API responses).
- Nameserver / DNS management, auto-renew toggle, WHOIS lookup, registry event log, domain-level audit log.
- Registrar account balances and credit transfers between registrar accounts.
- Nightly **SSL monitoring** on every domain.
- Automatic expiry reminders and automatic renewal processing.

**Hosting**
- Connect your WHM/cPanel server (API token stored encrypted).
- **Accounts** — cPanel accounts created automatically the moment an invoice is paid.
- **Manage Services** — suspend, unsuspend, terminate, change package (with prorated billing on upgrade/downgrade).
- **Discover Accounts** — scan an existing WHM server and import accounts that aren't in MoBilling yet. This is the migration tool.
- **One-click SSO** — clients jump straight into cPanel, webmail, File Manager or phpMyAdmin from the portal, with no password ever shared.
- Nightly reconciliation between MoBilling and the live server.
- Full provisioning log for every automated action.
- **WHMCS import** — clients, services, invoices, payments and domains migrate across, and clients keep their existing portal passwords.

> **Content angles:** "Register .co.tz directly at the registry — no middleman." · "Client pays at 11 p.m., hosting is live at 11:01 p.m." · "Already on WHMCS? We import everything, and your clients keep their passwords."

---

### 3.4 Client Portal (your clients' own login)

A complete self-service portal, white-labelled to the tenant's brand and reachable on the tenant's own domain. 22 screens, ~56 API endpoints.

Clients can: view a dashboard; browse and download **invoices, quotations and credit notes** as PDF; request an invoice cancellation; ask for a document to be resent; view **payment history and download receipts**; view a full **account statement**; **pay online** (M-Pesa / Pesapal / card); top up and spend from their **credit wallet**; browse the **catalogue and order services**; manage **subscriptions**; manage **hosting accounts** (with cPanel SSO); manage **domains** — check availability, order, renew, fetch the EPP transfer code, change nameservers, toggle auto-renew; access the **reseller programme** (status, subscribe, wholesale domain ordering and renewal); open and reply to **support tickets** with attachments; read **announcements** and the **knowledgebase**; edit their **profile**, change password, enable 2FA; and manage **sub-users** on their own account.

Portal self-registration is OTP-verified.

> **Content angle:** "Stop answering 'send me my invoice' on WhatsApp. They log in and get it themselves — at 2 a.m. if they want."

---

### 3.5 Public order flow (shopping cart)

A WHMCS-style storefront: `/order` → category → configure → domain → pay. Prospects choose a plan, pick a domain, apply a coupon, pay online, and the service provisions itself. No account needed to start.

---

### 3.6 Support

| Sub-module | What it does |
|---|---|
| **Support Tickets** | Full helpdesk: ticket numbers, departments, priorities, statuses, assignment, threaded replies, file attachments, e-mail notifications. Shared surface between staff and the portal. |
| **Canned Replies** | Saved response templates so the team answers common questions consistently and fast. |
| **Knowledgebase** | Categories and articles, published to the client portal — self-service deflection for repetitive questions. |

---

### 3.7 Engagement (sales, retention and marketing operations)

This group is what makes MoBilling different from every generic billing tool.

| Sub-module | What it does |
|---|---|
| **Satisfaction Calls** | Monthly customer-care calls **auto-scheduled** and assigned round-robin to staff. Log the outcome and a rating; daily reminders per user; history attached to the client record; a dedicated satisfaction report. |
| **Appointments** | Scheduled client meetings and visits. |
| **WhatsApp** | A lead pipeline for WhatsApp and social-ad enquiries: campaigns (with dates and budget), contacts, interaction logging, follow-up scheduling and conversion tracking. Every lead is tagged by where it came from — **WhatsApp ad, Instagram, Facebook, social media, direct, referral or other** — so you can report conversion by source and prove which channel actually pays. Messages route through a linked **MoSMS** account, so there is no per-tenant Meta setup. |
| **Field Marketing** | Door-to-door and field-sales management: a **session** (officer, date, area, summary, challenges, recommendations) containing individual **visits**, each with a status (interested / follow-up / converted). Per-officer conversion counts, field targets, and field follow-ups. Officers log from their phones. |
| **Social Media** | An in-house social content production board: platforms, posts (title, type, format, media type, scheduled date and time, brief, caption, hashtags), separate **design** and **content** workflow statuses, designer and copywriter assignment, per-platform publish toggles, weekly summary, and **targets** per platform. Also **client design orders** — design jobs sold to clients, with type, brief, reference, assigned designer, due date, revision count, revision notes, delivered file and price. |
| **Served Customers** | Walk-in / counter service logging: who was served, which services, on what date, plus a customer-feedback record per visit. Configurable service list. |

> **Content angles:** "Every door your team knocked on, on one map." · "We call every customer once a month — and the system decides whose turn it is." · "Sell design work? Track the brief, the designer, the revisions and the price in the same system that invoices it."

---

### 3.8 Statutory compliance

Built for Tanzania and Kenya statutory obligations.

- **Obligations** — recurring statutory items (VAT, PAYE, NSSF, NHIF, WCF, SDL, licences) with amount, cycle, issue date, auto-computed next due date, and configurable "remind N days before".
- **Schedule** — the compliance calendar: what falls due, when.
- **Bills** — the actual bills raised against those obligations.
- **Bill Categories** — organise obligations by type.
- **Payment History (Payments Out)** — what was paid, when, from which bank account, with proof.
- Automatic reminder e-mails/SMS before every deadline, and automatic generation of recurring bills.
- A **Statutory Compliance report** showing on-track / due-soon / overdue.

> **Content angle:** "The TRA deadline doesn't move. Neither does your reminder."

---

### 3.9 Expenses & petty cash

- **Expense Categories** and sub-categories.
- **Expenses** — amount, category, payment method, bank account, receipt attachment, and an **approval workflow**.
- **Petty Cash** — dedicated petty-cash accounts, top-ups, transactions and **reconciliation** records.
- Feeds the Expense Report and the Profit & Loss report.

---

### 3.10 Records & Verification

An operational-control module for businesses that run multiple systems, agencies or collection points.

- **Systems** — the systems/outlets you operate.
- **System Properties** — the properties/lines recorded against them.
- **System Records** — daily data entry: system, property, bank account, date, amount, notes, receipt attachment. Feeds a dedicated report and a dashboard breakdown.
- **System Verifications** — register a system/domain, assign it to a staff member, and require a **daily verification report**. Automatic reminders go out at **20:00 and again at 22:00 East Africa time** until it's submitted.
- **My Verifications** — the assigned staff member's own daily checklist.

> **Content angle:** "Every branch checks in daily. If they don't, the system chases them twice — before you have to."

---

### 3.11 Reports (13)

Each report ships with stat cards, interactive charts, a detail table, date-range filtering with presets, and **CSV export**.

1. **Revenue Summary** — monthly invoiced vs collected, with growth trend
2. **Outstanding & Aging** — 1–30 / 31–60 / 61–90 / 90+ day bands
3. **Client Statement** — per-client ledger with running balance
4. **Payment Collection** — payment-method breakdown and daily trend
5. **Expense Report** — by category and sub-category, monthly trend
6. **Profit & Loss** — revenue less expenses and bill payments
7. **Statutory Compliance** — on track / due soon / overdue
8. **Subscription Report** — active subscriptions, renewals, revenue forecast
9. **Collection Effectiveness** — follow-up outcomes and promise-fulfilment rate
10. **Satisfaction Report** — call volume, average rating, satisfaction and complaint rates
11. **Communication Log** — e-mail/SMS delivery rates by channel and type
12. **System Records Report**
13. **System Verifications Report**

---

### 3.12 Communications

| Sub-module | What it does |
|---|---|
| **SMS** | SMS credits, purchase packages, delivery log and balance. Balance appears on the dashboard. |
| **Broadcast** | Send to all clients or a selected set via **e-mail, SMS, WhatsApp or all channels**, with preset templates. Every send records which clients received it and which failed, stores the **reason for each failure**, and can be **retried against the failed recipients only** — a retry is linked back to the original broadcast, so you never re-spam the people who already got it. |
| **Announcements** | Publish notices to the client portal, with publish scheduling. |
| **Notifications** | In-app notification bell with unread counts, plus **Firebase push notifications** to the mobile apps across every backend notification. |
| **E-mail** | Tenant-configurable SMTP with a platform fallback, editable templates, and a test-send button. |

---

### 3.13 HR & Payroll

A genuine HR suite, not a token module.

| Sub-module | What it does |
|---|---|
| **Staff Reports** | Daily/periodic staff reporting with a supervisor hierarchy: staff submit, supervisors review and reply. Automated reminders before the deadline, and **automatic penalty deductions** applied after the deadline passes for missing reports (idempotent, runs 00:30 daily). Configurable settings and holidays. |
| **Attendance** | Check-in/check-out, statuses (present, late, absent, leave, sick, field), status notes, excused-day handling, sheet import, **and a live HIKVISION biometric-device webhook** that imports device events every 5 minutes. Automatic late/absence penalties applied nightly at 22:30. |
| **Staff Targets** | Per-staff targets with criteria, self-submission and supervisor verification. |
| **Leave** | Leave types (days per year, paid/unpaid, colour), balances, requests, and a review workflow. |
| **Payroll** | Full payroll runs producing per-employee payslips: basic salary, allowances (with breakdown), gross pay, employee statutory deductions, taxable income, **PAYE computed from configurable progressive brackets**, other deductions, net pay, employer statutory contributions and total employer cost. Includes **loans** (with repayment schedules) and **salary advances**. Payslips export to PDF. |
| **Employee Profiles** | Employment records attached to users. |

**Default PAYE brackets shipped (Tanzania, monthly, TZS):**

| Band | Rate | Base deduction |
|---|---|---|
| 0 – 270,000 | 0 % | 0 |
| 270,001 – 520,000 | 8 % | 0 |
| 520,001 – 760,000 | 20 % | 20,000 |
| 760,001 – 1,000,000 | 25 % | 68,000 |
| Above 1,000,000 | 30 % | 128,000 |

Brackets are editable per tenant. Statutory rates are configured per tenant too — employee %, employer %, and whether the contribution reduces taxable income — and applied to every payroll run.

**Tanzania rates currently configured in the live system:**

| Contribution | Employee | Employer | Reduces taxable income |
|---|---|---|---|
| **NSSF** | 10% | 10% | Yes |
| **WCF** | — | 0.5% | No |
| **SDL** | — | 3.5% | No |

> **Content angle:** "NSSF 10/10, WCF 0.5%, SDL 3.5% — set once, applied to every payslip, and editable when the rate changes."

> **Content angle:** "PAYE, NSSF and WCF calculated for you — with your own rates, not hard-coded ones."

---

### 3.14 Automation

The engine room. A read-only **forecast** screen shows exactly what the reminder crons will send over the next 1–60 days, exportable as PDF or CSV, plus cron logs and full communication history.

**20 scheduled jobs run every day:**

| Time | Job | What it does |
|---|---|---|
| 00:30 | `staff-reports:apply-penalties` | Charge deductions for missing staff reports |
| 05:00 | `license:check` | Validate self-hosted licences |
| 05:30 | `hosting:reconcile` | Reconcile cPanel accounts with the live server |
| 05:45 | `domains:sync` | Sync domain state from the registry |
| 06:00 | `subscriptions:expire` | Expire lapsed tenant subscriptions |
| 06:30 | `domains:process-renewals` | Auto-renew domains (drawing on the client wallet) |
| 07:00 | `invoices:process-recurring` | Generate recurring invoices |
| 07:15 | `satisfaction-calls:schedule` | Schedule the month's customer-care calls |
| 07:30 | `followups:process` | Process due collection follow-ups |
| 08:00 | `bills:send-reminders` | Statutory bill reminders |
| 08:30 | `invoices:process-overdue` | Overdue notices / dunning |
| 08:45 | `domains:send-expiry-reminders` | Domain expiry reminders |
| 09:00 | `bills:generate-recurring` | Generate recurring statutory bills |
| 09:30 | `subscriptions:suspend-unpaid` | Suspend unpaid services after the grace period |
| 09:45 | `staff-reports:send-reminders` | Remind staff to submit reports |
| 10:00 | `subscriptions:terminate-abandoned` | Terminate long-abandoned services |
| 20:00 | `verifications:send-reminders` | First daily verification reminder |
| 22:00 | `verifications:send-reminders --second` | Final daily verification reminder |
| 22:30 | `attendance:apply-penalties` | Apply late/absence penalties |
| every 5 min | `attendance:import-device-events` | Pull biometric device check-ins |

> **Content angle:** "While you sleep, MoBilling invoices, reminds, renews, suspends and reconciles. Here's the actual timetable." — this table is *excellent* social content on its own.

---

### 3.15 Account & platform administration

- **Subscription** — current plan, history, checkout, invoice download, bank-transfer proof upload.
- **Team (Users)** — staff accounts, supervisors, activation.
- **Roles** — build custom roles from 250+ granular permissions; menu visibility and action rights are separate.
- **Active Sessions** — see and revoke logged-in devices.
- **Settings** — company profile and branding, e-mail/SMTP, templates, reminder rules, payment methods, WhatsApp/MoSMS linking, users, plus the reference CRUDs (Systems, Bank Accounts, System Properties).
- **Security** — Sanctum tokens, optional **two-factor authentication** with recovery codes (staff *and* portal users), idle-session timeout, encrypted storage for API tokens and EPP auth codes.

### 3.16 Super-admin console (Moinfotech's own control panel)

Tenants (create, edit, activate/deactivate, **promote an existing client into a full independent tenant**), per-tenant users, per-tenant e-mail settings and templates, per-tenant SMS settings with manual recharge/deduct, **impersonation** of a tenant or a specific user (with a clear exit banner), subscription plans, tenant subscriptions and manual extension, bank-transfer payment confirmation, currencies, SMS packages and purchase history, self-hosted **licences** (issue, unbind domain), **licence plans**, **releases** (the "check for updates" catalogue for self-hosted installs), role templates, tenant permissions and platform settings.

### 3.17 Self-hosted installer

A guided browser installer for on-premise customers: requirements check → database connection test → migrate → licence key check → create the first tenant. The whole installer surface locks itself out permanently once a tenant exists.

### 3.18 Mobile

A Flutter codebase with shared packages (`mobilling_api`, `mobilling_auth`, `mobilling_ui`). The **staff app** is at parity with the web sidebar and in active development; the **client portal app** is planned. Push notifications (Firebase, Android) are already wired across every backend notification.

---

## 4. Integrations

| Integration | Purpose |
|---|---|
| **Pesapal** | Card, M-Pesa and mobile-money collection, with IPN webhooks. Platform-level and per-tenant Pesapal accounts both supported. |
| **TCRA / tzNIC (EPP / FRED)** | Direct .tz domain registration, renewal, transfer, nameserver and contact management |
| **WHM / cPanel** | Account creation, suspension, termination, package change, SSO |
| **MoSMS** | SMS and WhatsApp messaging |
| **HIKVISION** | Biometric attendance devices (token-secured webhook) |
| **Firebase Cloud Messaging** | Mobile push notifications |
| **SMTP** | Per-tenant e-mail with platform fallback |
| **WHMCS** | One-way import of clients, services, invoices, payments and domains |

---

## 5. Who it's for (audience segments for targeting)

1. **Hosting and domain resellers** — the sharpest fit. Direct replacement for WHMCS, with no licence fee, .tz registry access built in, and M-Pesa/Pesapal native.
2. **ISPs and IT service companies** — recurring subscriptions, provisioning, support desk, field teams.
3. **SMEs with recurring billing** — schools, gyms, security firms, waste collection, equipment leasing, service contractors.
4. **Businesses with statutory pain** — anyone tracking VAT, PAYE, NSSF, NHIF, WCF and SDL deadlines manually.
5. **Companies with field sales teams** — door-to-door, agent networks, distribution.
6. **Marketing and design agencies** — the social-media production board and client design orders are built for exactly this.
7. **Multi-branch operations** — daily system verification and records.

---

## 6. The strongest differentiators (use these as headline hooks)

1. **No WHMCS licence fee.** Same job, no recurring foreign licence bill.
2. **Direct .tz registry access over EPP.** Not a reseller of a reseller.
3. **M-Pesa and Pesapal native.** Built here, for here.
4. **Swahili support.** "Kabisa" — the support team works in both languages.
5. **It's not just billing.** HR, payroll, statutory, field marketing and social-media production in the same login.
6. **20 automated jobs a day.** The system works the night shift.
7. **250+ granular permissions.** Real role separation, not "admin or not admin".
8. **Full white-label.** Your brand, your domain, your prices, your margin.
9. **Migration is solved.** WHMCS import keeps clients' existing portal passwords; WHM discovery imports live cPanel accounts.
10. **Your data stays yours.** If a subscription lapses the account goes read-only so you can still export — nothing is deleted.

---

## 7. Proof points and figures safe to publish

**Product scale**

- 7-day free trial, no card required
- 133 API controllers · 274 database tables · 90+ staff screens · 22 portal screens
- 13 standard reports, all CSV-exportable
- 20 automated daily jobs
- **273 granular permissions** (52 menu-level, 221 action-level) — exact figure, verified
- ~56 client-portal API endpoints
- Payment methods: M-Pesa, Pesapal, card, bank transfer, cash, cheque, client credit wallet
- Registry: TCRA/tzNIC over EPP
- Currencies supported: TZS (active), plus KES, USD, EUR, GBP, RWF and UGX available

**Live production load — the strongest proof you now have**

These are real records in the live system, not demo data. Use them as "the system runs this today", and round them in public copy.

| Measure | Live count |
|---|---|
| Businesses running on MoBilling (tenants) | 6 |
| Client records under management | 286 |
| Invoices, quotations and credit notes issued | 1,356 |
| Active recurring subscriptions | 551 |
| Domains under management | 247 (191 active) |
| Hosting accounts provisioned | 140 (134 active) |
| Staff user accounts | 42 |

> **The industry spread is the story, not the totals.** The live tenants include a hosting and IT company, a transporters' association and **ARG SPARKLES — a pest-control products business selling rodent bait and sprays**. That last one is the proof that MoBilling is not a hosting-only tool: the same catalogue, invoicing and subscription engine sells "Shenke Ndogo" bait at TZS 700 a piece and a 350,000 carton of spray. Get written consent before naming any of them publicly.

---

## 8. Accuracy guardrails — do not overstate

Marketing must stay true to what actually ships:

- **Only .tz domains register automatically.** `.com`, `.net` and `.org` are flagged `is_unmanaged` — there is no registrar driver for them. They can be sold and invoiced, but staff must register them by hand at an outside registrar (GoDaddy, Namecheap) and then mark the domain registered. The order shows an "Awaiting Registration" state in the meantime. **Never advertise instant or automatic .com registration.**
- **Perpetual self-hosted licences do not exist.** Monthly, quarterly, semi-annual and annual are priced and sellable; the perpetual field is empty, so the Buy Licence page does not offer it.
- **The client mobile app is not released yet.** The staff app is in development. Do not advertise app-store availability.
- Plan feature gating is currently enforced for four things only: Advanced Reports, SMS, Multi-user access and Custom branding. "Unlimited invoices/clients/users" and support-level promises are commercial commitments, not technical limits enforced in code.
- The landing-page testimonials (Amina Hassan, David Ochieng, Fatuma Kombo) are **placeholder copy**, not real customers. Do not reuse them as testimonials in ads — replace them with real, consented ones.
- Dashboard preview figures on the landing page are illustrative sample data.
- The live product catalogue (section 9.5) still contains legacy rows imported from WHMCS — **this was not cleaned in the new database.** "Web Hosting University, yearly" still exists at five prices (16.20 / 40,500 / 49,999 / 60,000 / 64,400), a TZS 2.00 monthly hosting plan is still portal-visible, and there is now a category literally named `1`. Clean it before publishing any price list drawn from it.
- **The reseller domain margin is thin.** Wholesale .co.tz is 18,750 against 19,999 retail — about TZS 1,250 a domain. Sell the reseller programme on hosting margin and own-brand pricing, not on domain spread.
- **The database is five migrations ahead of the `mobile-design-system` branch** (WhatsApp broadcasts, broadcast recipient tracking and failure reasons, wider WhatsApp lead sources, unmanaged TLDs). Anything documented from those five features is real in production but will not be found in this branch's code.

---

# 9. Complete package and pricing catalogue

All prices in **Tanzanian Shillings (TZS)** unless stated. TZS is the only currency currently active.

## 9.1 MoBilling Cloud — hosted SaaS plans

Billing cycle: **every 30 days**. Free trial: **7 days**, no card required.

| Plan | Price (per 30 days) | Positioning | Included |
|---|---|---|---|
| **Starter** | **TZS 10,000** | Small businesses just getting started | Up to 50 invoices/month · Up to 20 clients · E-mail support · Basic reports |
| **Professional** | **TZS 25,000** | Growing businesses that need more power | Unlimited invoices · Unlimited clients · SMS notifications · Advanced reports · Priority support |
| **Business** ⭐ | **TZS 50,000** | Established businesses (the upsell target) | Everything in Professional · Multi-user access · Custom branding · API access · Dedicated support |
| **Enterprise** | **TZS 100,000** | Large organisations | Everything in Business · Unlimited users · White-label PDFs · Custom integrations · SLA guarantee · 24/7 support |

**Annualised for content:** Starter ≈ TZS 120,000/yr · Professional ≈ 300,000/yr · Business ≈ 600,000/yr · Enterprise ≈ 1,200,000/yr.

**What is technically gated between tiers** (everything else is available on every plan):

| Capability | Starter | Professional | Business | Enterprise |
|---|:--:|:--:|:--:|:--:|
| Core billing, invoicing, clients, domains, hosting, HR, statutory | ✅ | ✅ | ✅ | ✅ |
| Advanced reports (P&L, statutory, subscription, expense, communication, satisfaction, records, verifications) | — | ✅ | ✅ | ✅ |
| SMS module | — | ✅ | ✅ | ✅ |
| Multi-user access (Team + Roles) | — | — | ✅ | ✅ |
| Custom branding | — | — | ✅ | ✅ |

Payment for subscriptions: Pesapal (M-Pesa/card) or bank transfer with proof upload.
Platform bank details on file: **CRDB Bank — Moinfotech Company Ltd — Dar es Salaam branch.**

---

## 9.2 MoBilling Self-Hosted — licence plans

Install MoBilling on your own server. Three product lines, five possible billing periods each: **monthly, quarterly, semi-annual, annual, perpetual (one-time)**. Buy online at `/buy-license`, receive the licence key immediately, then follow the installation guide. Licences bind to a domain and check in daily.

| Product | Name | Scope |
|---|---|---|
| `lite` | **MoBilling Lite** | Billing & CRM basics — no domains or hosting |
| `reseller` | **MoBilling Reseller** | The WHMCS-style toolkit, including domains & hosting |
| `general` | **MoBilling Complete** | The full platform — everything |

**Prices are now live and sellable.** All amounts in TZS.

| Product | Monthly | Quarterly | Semi-annual | Annual | Perpetual |
|---|---|---|---|---|---|
| **MoBilling Lite** | **10,000** | 25,000 | 45,000 | **80,000** | not offered |
| **MoBilling Reseller** | **15,000** | 30,000 | 50,000 | **95,000** | not offered |
| **MoBilling Complete** | **25,000** | 55,000 | 95,000 | **175,000** | not offered |

**Effective annual cost** (the number to lead with — annual is a real discount, not a rounding):

| Product | 12 × monthly | Annual price | Saving |
|---|---|---|---|
| Lite | 120,000 | 80,000 | **33% off** |
| Reseller | 180,000 | 95,000 | **47% off** |
| Complete | 300,000 | 175,000 | **42% off** |

> **Perpetual licences are not offered.** The price field is empty for all three products, so the Buy Licence page shows only the four recurring periods. If a prospect asks for a one-time purchase, it does not exist today — take the enquiry, do not quote.

> **Note the positioning:** self-hosted Lite (TZS 10,000/month) matches hosted Starter exactly, and self-hosted Complete (25,000/month) matches hosted Professional. The self-hosted line is priced to compete with the cloud line, not to undercut it — the customer pays the same and supplies their own server.

---

## 9.3 SMS packages (volume-tiered)

Price per SMS falls automatically as volume rises. Buy credits from inside MoBilling; balance shows on the dashboard.

| Package | Quantity band | Price per SMS | Example bundle cost |
|---|---|---|---|
| **Personal** | 1 – 5,999 | **TZS 20** | 1,000 SMS = TZS 20,000 |
| **Standard** | 6,000 – 54,999 | **TZS 19** | 10,000 SMS = TZS 190,000 |
| **Plus** | 55,000 – 409,999 | **TZS 18** | 100,000 SMS = TZS 1,800,000 |
| **Premier** | 410,000 and above | **TZS 17** | 500,000 SMS = TZS 8,500,000 |

---

## 9.4 Domain pricing (platform default retail)

Register, renew and transfer are the same price. Terms of **1 to 10 years**. Tenants running white-label can override every one of these with their own retail price and set a separate reseller price.

| TLD | Register | Renew | Transfer |
|---|---|---|---|
| **.tz** (second level) | **TZS 79,999** | 79,999 | 79,999 |
| **.co.tz** | **TZS 18,999** | 18,999 | 18,999 |
| **.or.tz** | TZS 18,999 | 18,999 | 18,999 |
| **.ac.tz** | TZS 18,999 | 18,999 | 18,999 |
| **.sc.tz** | TZS 18,999 | 18,999 | 18,999 |
| **.ne.tz** | TZS 18,999 | 18,999 | 18,999 |
| **.me.tz** | TZS 18,999 | 18,999 | 18,999 |
| **.tv.tz** | TZS 18,999 | 18,999 | 18,999 |
| **.info.tz** | TZS 18,999 | 18,999 | 18,999 |
| **.hotel.tz** | TZS 18,999 | 18,999 | 18,999 |
| **.com** | **TZS 55,000** | 55,000 | 55,000 |
| **.net** | TZS 55,000 | 55,000 | 55,000 |
| **.org** | TZS 55,000 | 55,000 | 55,000 |

### Moinfotech's own retail pricing (overrides the platform defaults)

**This is what sales must quote — not the platform table above.** Moinfotech has set its own tenant-level row for every TLD, and the tenant row always wins.

| TLD | Register / Renew | **Transfer in** | Reseller (wholesale) | Fulfilment |
|---|---|---|---|---|
| **.tz** | **TZS 95,000** | **Free** | 75,000 | Automatic via EPP |
| **.co.tz** | **TZS 19,999** | **Free** | 18,750 | Automatic via EPP |
| .or.tz · .ac.tz · .sc.tz | TZS 19,999 | Free | 18,750 | Automatic via EPP |
| .ne.tz · .me.tz · .tv.tz | TZS 19,999 | Free | 18,750 | Automatic via EPP |
| .info.tz · .hotel.tz | TZS 19,999 | Free | 18,750 | Automatic via EPP |
| **.com · .net · .org** | **TZS 55,000** | 55,000 | 45,000 | **Manual — staff registers by hand** |

> **Free transfers are a real, unexploited hook.** Every .tz transfer-in is priced at zero, against a 19,999 registration. "Hamisha domain yako ya .co.tz kwetu bure" is a campaign nobody is running yet.

> **Reseller margin, stated plainly:** a reseller buys .co.tz at 18,750 and the recommended retail is 19,999 — about TZS 1,250 a domain. The real reseller margin is in hosting and in setting their *own* retail price, not in the wholesale domain spread. Don't oversell the domain margin.

> **Content angle:** ".co.tz kwa TZS 19,999 — imesajiliwa moja kwa moja kwenye registry, iko live ndani ya dakika."

---

## 9.5 Moinfotech's own service catalogue (sold through MoBilling)

This is the live, portal-visible catalogue for **Moinfotech Company Limited**. It was imported from WHMCS and **contains duplicates and stale rows — clean it before publishing.** Rows below are the ones that read as current.

### Web hosting (cPanel)

| Package | Cycle | Price |
|---|---|---|
| Web Hosting University | monthly | TZS 5,000 |
| Web Hosting Premier | monthly | TZS 13,000 |
| Web Hosting Professional | quarterly | TZS 34,000 |
| Web Hosting University | quarterly | TZS 80,500 |
| Web Hosting University | yearly | TZS 40,500 – 80,500 *(several conflicting rows: 40,500 / 49,999 / 60,000 / 64,400 / 80,500 — resolve before publishing)* |
| Web Hosting Personal | yearly | TZS 120,000 |
| Web Hosting Professional | yearly | TZS 102,000 |
| Web Hosting Plus | yearly | TZS 150,000 |
| Web Hosting Premier | yearly | TZS 200,000 – 256,000 |
| Web Hosting System | yearly | TZS 216,000 |
| Web Hosting Plus (cPanel tier) | yearly | TZS 500,000 |
| University Offer Hosting Package | yearly | TZS 80,500 |
| Web Hosting Backup 5 GB | yearly | TZS 30,000 |
| Kitonga Web Hosting *(new)* | yearly | TZS 119,999 |
| Kitonga Business Email *(new)* | yearly | TZS 99,000 |
| Linux Shared Premier *(new)* | yearly | TZS 324,000 |

### Business e-mail

| Package | Cycle | Price |
|---|---|---|
| Business Email Starter | yearly | TZS 30,000 (entry) / 60,000 / 80,500 *(duplicate rows)* |
| Business Email Medium | yearly | TZS 60,000 – 100,000 |
| Business Email Premier | yearly | TZS 130,000 |
| Business Email Plus | yearly | TZS 350,000 |

### Domains (catalogue entries)

| Item | Cycle | Price |
|---|---|---|
| Domain Registration (.tz) | yearly | TZS 20,000 |
| Domain Registration .COM | yearly | TZS 55,000 |

### Reseller hosting

| Package | Cycle | Price |
|---|---|---|
| Reseller Membership | yearly | TZS 50,000 |
| Linux Reseller Starter | yearly | TZS 450,000 |
| Linux Reseller Medium | yearly | TZS 750,000 |
| Linux Reseller Premium | yearly | TZS 950,000 |
| Linux Reseller Business | yearly | TZS 1,700,000 |

### Dedicated / managed Linux servers

| Package | Cycle | Price |
|---|---|---|
| Linux MIT 500 | yearly | TZS 2,150,000 |
| Linux MIT 600 | yearly | TZS 2,850,000 |
| Linux MIT 700 | yearly | TZS 3,600,000 |
| Linux Server — MIT 450 | yearly | TZS 3,600,000 |
| Linux Server — MIT 550 | yearly | TZS 4,650,000 |
| Linux Server — MIT 650 | yearly | TZS 6,100,000 |

### Design & development (one-off)

| Service | Price |
|---|---|
| Reseller Design | TZS 250,000 |
| Static Website Design | TZS 500,000 |
| Web Development | TZS 150,000 |
| E-commerce Website Design | TZS 1,800,000 |

### Messaging

| Service | Unit | Price |
|---|---|---|
| MoSMS | per SMS | TZS 20 |

---

## 10. Content angles by module — a starter bank

| Module | Hook |
|---|---|
| Automation | "20 jobs run every night so you don't have to. Here's the timetable." |
| Domains | "Register .co.tz at TZS 19,999 — directly at the registry, live in minutes." |
| Domain transfers | "Hamisha .co.tz yako kwetu — bure kabisa." Free transfer-in is priced into the system and nobody is advertising it. |
| Self-hosted | "Your server, your data, your rules — from TZS 80,000 a year." |
| Broadcast | "Send to 300 clients. See exactly who didn't get it, and why. Retry just those." |
| Lead sources | "Which advert actually paid? WhatsApp, Instagram, Facebook or referral — tagged per lead." |
| Hosting | "Client pays at 11 p.m. The cPanel account is live at 11:01." |
| WHMCS migration | "Moving off WHMCS? Your clients keep their passwords." |
| Client portal | "Stop sending invoices on WhatsApp. They log in and take them." |
| Statutory | "PAYE, VAT, NSSF, WCF — the deadline doesn't move, and neither does your reminder." |
| Payroll | "Payslips with your own PAYE brackets, not someone else's." |
| Collection | "Every promise to pay, recorded — and measured." |
| Field marketing | "Every door your team knocked on, logged from their phone." |
| Satisfaction calls | "We call every customer once a month. The system picks whose turn it is." |
| Social media | "The tool we sell also runs our own content calendar." |
| Permissions | "250 permissions. Your cashier will never see payroll." |
| Reports | "13 reports. All exportable. All filtered by date range." |
| White-label | "Your brand, your prices, your margin. We run the machinery." |
| Pricing | "From TZS 10,000 a month. Seven days free, no card." |
| Swahili support | "Support kwa Kiswahili — kabisa." |

---

## 11. Contact details for creatives

- **Website:** mobilling.co.tz · moinfo.co.tz
- **Phone / WhatsApp:** +255 689 011 111
- **Office:** Njuweni Hotel, 1st Floor, Room 134, Kibaha, Tanzania
- **Bank (for platform payments):** CRDB Bank — Moinfotech Company Ltd — Dar es Salaam

---

*Generated from the MoBilling codebase and live database. Where the code and this document disagree, the code is right.*
