# MoBilling — Billing & Statutory Compliance

A multi-tenant billing and statutory compliance system built for Kenyan businesses. Manage invoices, quotations, statutory bills, expenses, subscriptions, and payments — all in one place.

## Tech Stack

| Layer | Technology |
|-------|------------|
| Frontend | React 19 + Vite + Mantine UI v8 |
| Backend | Laravel 12 (PHP) |
| Database | MySQL |
| Auth | Laravel Sanctum (token-based) |
| Charts | Recharts |
| PDF | Laravel DomPDF |
| Animations | Framer Motion |

## Project Structure

```
billing/
├── mobilling-ui/          # React frontend (Vite)
│   ├── public/            # Static assets (logo, etc.)
│   └── src/
│       ├── api/           # Axios API clients
│       ├── components/    # Layout, Dashboard, Billing, Reports, etc.
│       ├── context/       # AuthContext (Sanctum)
│       ├── hooks/         # Custom React hooks
│       └── pages/         # Route pages
│           ├── admin/     # Super admin pages
│           └── reports/   # 10 report pages
├── unganisha-api/         # Laravel backend
│   ├── app/Http/Controllers/
│   ├── app/Models/
│   ├── app/Services/
│   ├── database/migrations/
│   └── routes/api.php
└── unganisha-billing-statutory.md  # Original spec
```

## Features

### Core Billing
- **Invoicing** — Professional invoices with automatic numbering and tax calculations
- **Quotations & Proformas** — Generate quotes that convert to invoices in one click
- **Payment Tracking** — M-Pesa, bank transfer, cash, cheque reconciliation
- **Client Management** — Client directory with KRA PINs and billing history
- **Products & Services** — Product catalog with pricing and billing cycles
- **Client Subscriptions** — Recurring billing with auto-generated next-bill schedule

### Statutory & Expenses
- **Statutory Bills** — Track NHIF, NSSF, PAYE, VAT with due-date reminders and auto-generation
- **Expense Management** — Track expenses by category and sub-category with payment methods
- **Bill Categories** — Organize statutory obligations by type

### Collection & Automation
- **Collection Dashboard** — Real-time view of today's due, overdue, and upcoming invoices
- **Follow-up Tracking** — Log calls, record outcomes (promised, paid, no answer), track promise fulfillment
- **Automation** — Automated overdue reminders, cron job logs, and communication history
- **Broadcast Messaging** — Send announcements to all or selected clients via email/SMS/both with preset templates and delivery tracking

### Reports (10 Reports)
- **Revenue Summary** — Monthly invoiced vs collected with growth trends
- **Outstanding & Aging** — Overdue invoices by age bands (1-30, 31-60, 61-90, 90+ days)
- **Client Statement** — Per-client ledger with running balance
- **Payment Collection** — Payment method breakdown and daily trends
- **Expense Report** — Expenses by category/sub-category with monthly trends
- **Profit & Loss** — Revenue minus expenses and bill payments
- **Statutory Compliance** — Obligation status (on track, due soon, overdue)
- **Subscription Report** — Active subscriptions, renewals, and revenue forecast
- **Collection Effectiveness** — Follow-up outcomes and promise fulfillment rate
- **Communication Log** — Email/SMS delivery rates by channel and type

All reports include stat cards, interactive charts (Recharts), detail tables, date range filtering with presets, and CSV export.

### Platform
- **Multi-tenant** — Isolated workspaces per business with tenant-scoped data
- **Roles & Permissions** — Custom roles with granular menu and action permissions per tenant
- **Super Admin** — Manage tenants, subscription plans, currencies, SMS packages, platform settings, tenant permissions
- **Tenant Subscriptions** — Trial periods, plan-based billing via Pesapal integration
- **SMS** — SMS credits via reseller API with package purchasing
- **Email** — Tenant-configurable SMTP with platform fallback
- **Broadcast Messaging** — Send announcements to all or selected clients via email/SMS/both with preset templates
- **Notifications** — In-app notification bell with unread counts
- **Dark Mode** — System-aware with manual toggle
- **Landing Page** — Public page with hero, features grid, and scroll animations

## Getting Started

### Prerequisites

- PHP 8.2+, Composer
- Node.js 18+, npm
- MySQL 8+

### Backend Setup

```bash
cd unganisha-api
composer install
cp .env.example .env
php artisan key:generate

# Configure .env with your MySQL credentials, then:
php artisan migrate --seed
php artisan serve
```

### Frontend Setup

```bash
cd mobilling-ui
npm install
cp .env.example .env.local   # Set VITE_API_URL=http://localhost:8000/api

npm run dev
```

### Default Credentials

| User | Email | Password |
|------|-------|----------|
| Admin | admin@moinfotech.com | password |
| Test | test@mobilling.com | password |

Or register a new account at `/register`.

## Routes

### Frontend

| Path | Access | Description |
|------|--------|-------------|
| `/` | Public | Landing page |
| `/login` | Public | Sign in |
| `/register` | Public | Create account |
| `/dashboard` | Protected | Dashboard overview |
| `/collection` | Protected | Collection dashboard |
| `/followups` | Protected | Follow-up call tracking |
| `/clients` | Protected | Client management |
| `/clients/:id` | Protected | Client profile |
| `/product-services` | Protected | Products & services |
| `/quotations` | Protected | Quotation documents |
| `/proformas` | Protected | Proforma invoices |
| `/invoices` | Protected | Invoice documents |
| `/payments-in` | Protected | Incoming payments |
| `/client-subscriptions` | Protected | Client subscriptions |
| `/next-bills` | Protected | Auto-generated next bills |
| `/statutories` | Protected | Statutory obligations |
| `/statutory-schedule` | Protected | Upcoming statutory schedule |
| `/bills` | Protected | Statutory bills |
| `/bill-categories` | Protected | Bill categories |
| `/payments-out` | Protected | Outgoing payments |
| `/expense-categories` | Protected | Expense categories |
| `/expenses` | Protected | Expense records |
| `/reports/*` | Protected | 10 report pages (see Reports section) |
| `/broadcast` | Protected | Broadcast messaging |
| `/automation` | Protected | Automation dashboard |
| `/sms` | Protected | SMS credit management |
| `/subscription` | Protected | Tenant subscription |
| `/users` | Protected | Team management |
| `/roles` | Protected | Role & permission management |
| `/settings` | Protected | Company, profile, reminders, templates, payment methods, email |

### API

All API routes are prefixed with `/api` and require Sanctum authentication (except auth endpoints).

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/auth/register` | Register new tenant + user |
| POST | `/auth/login` | Login, returns token |
| POST | `/auth/logout` | Revoke token |
| GET | `/auth/me` | Current user + tenant |
| CRUD | `/clients` | Client management |
| CRUD | `/product-services` | Products & services |
| CRUD | `/documents` | Documents (invoices, quotations, proformas) |
| CRUD | `/payments-in` | Incoming payments |
| CRUD | `/client-subscriptions` | Client subscriptions |
| CRUD | `/statutories` | Statutory obligations |
| CRUD | `/bills` | Statutory bills |
| CRUD | `/bill-categories` | Bill categories |
| CRUD | `/payments-out` | Outgoing payments |
| CRUD | `/expense-categories` | Expense categories |
| CRUD | `/expenses` | Expenses |
| GET | `/dashboard/summary` | Dashboard stats |
| GET | `/collection/dashboard` | Collection dashboard |
| GET/POST | `/followups` | Follow-up management |
| GET/POST | `/broadcasts` | Broadcast messaging (list history / send) |
| GET | `/automation/summary` | Automation dashboard |
| GET | `/reports/revenue-summary` | Revenue report |
| GET | `/reports/outstanding-aging` | Aging report |
| GET | `/reports/client-statement` | Client statement |
| GET | `/reports/payment-collection` | Payment collection report |
| GET | `/reports/expense-report` | Expense report |
| GET | `/reports/profit-loss` | Profit & loss report |
| GET | `/reports/statutory-compliance` | Statutory compliance report |
| GET | `/reports/subscription-report` | Subscription report |
| GET | `/reports/collection-effectiveness` | Collection effectiveness report |
| GET | `/reports/communication-log` | Communication log report |
| CRUD | `/roles` | Role management |
| GET | `/available-permissions` | Available permissions list |
| PUT | `/settings/company` | Update company profile |
| PUT | `/settings/profile` | Update user profile |

## Architecture Notes

- **Multi-tenancy**: Shared database with `tenant_id` column on every table. The `BelongsToTenant` trait auto-scopes all queries.
- **UUIDs**: All primary keys use UUIDs via Laravel's `HasUuids` trait.
- **Auth flow**: Sanctum token stored in `localStorage`. `AuthContext` provides `user`, `login`, `register`, `logout`, and `refreshUser`.
- **Roles & Permissions**: Custom roles per tenant with granular permissions (menu visibility, CRUD actions, reports). The `permission` middleware gates API routes; the `usePermissions` hook gates UI elements. Super admins can configure which permissions are available to each tenant.
- **Protected routes**: `ProtectedRoute` wrapper redirects unauthenticated users to `/` (landing page). Supports `requiredRole` and `allowExpired` props.
- **Color scheme**: Persisted in `localStorage` via Mantine. Flash prevention script in `index.html`.
- **Reports**: All 10 reports accept `start_date` and `end_date` query params (default: current month). Frontend uses React Query with date-dependent query keys for auto-refetch.
- **Charts**: Recharts v3 for all data visualizations (BarChart, AreaChart, PieChart).
- **CSV Export**: Client-side CSV generation with proper escaping — no server dependency.
