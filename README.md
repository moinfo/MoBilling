# MoBilling — Billing & Statutory Compliance

A multi-tenant billing and statutory compliance system built for Kenyan businesses. Manage invoices, quotations, statutory bills, and payments — all in one place.

## Tech Stack

| Layer | Technology |
|-------|------------|
| Frontend | React 19 + Vite + Mantine UI v8 |
| Backend | Laravel 12 (PHP) |
| Database | MySQL |
| Auth | Laravel Sanctum (token-based) |
| Animations | Framer Motion |
| PDF | Laravel DomPDF |

## Project Structure

```
billing/
├── mobilling-ui/          # React frontend (Vite)
│   ├── public/            # Static assets (logo, etc.)
│   └── src/
│       ├── api/           # Axios API clients
│       ├── components/    # Layout (AppShell, ProtectedRoute)
│       ├── context/       # AuthContext (Sanctum)
│       └── pages/         # Route pages
├── unganisha-api/         # Laravel backend
│   ├── app/Http/Controllers/
│   ├── app/Models/
│   ├── database/migrations/
│   └── routes/api.php
└── unganisha-billing-statutory.md  # Original spec
```

## Features

- **Invoicing** — Professional invoices with automatic numbering and tax calculations
- **Quotations & Proformas** — Generate quotes that convert to invoices in one click
- **Statutory Bills** — Track NHIF, NSSF, PAYE, VAT with due-date reminders
- **Payment Tracking** — M-Pesa, bank transfer, cash, cheque reconciliation
- **Client Management** — Client directory with KRA PINs and billing history
- **Multi-tenant** — Isolated workspaces per business with tenant-scoped data
- **Settings** — Company profile and user profile management (admin-gated)
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
| `/clients` | Protected | Client management |
| `/product-services` | Protected | Products & services |
| `/quotations` | Protected | Quotation documents |
| `/proformas` | Protected | Proforma invoices |
| `/invoices` | Protected | Invoice documents |
| `/bills` | Protected | Statutory bills |
| `/payments-out` | Protected | Payment history |
| `/settings` | Protected | Company & profile settings |

### API

All API routes are prefixed with `/api` and require Sanctum authentication (except auth endpoints).

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/auth/register` | Register new tenant + user |
| POST | `/auth/login` | Login, returns token |
| POST | `/auth/logout` | Revoke token |
| GET | `/auth/me` | Current user + tenant |
| GET/POST | `/clients` | List / create clients |
| GET/POST | `/product-services` | List / create products |
| GET/POST | `/documents` | List / create documents |
| GET/POST | `/payments-in` | List / create incoming payments |
| GET/POST | `/bills` | List / create statutory bills |
| GET/POST | `/payments-out` | List / create outgoing payments |
| GET | `/dashboard/summary` | Dashboard stats |
| PUT | `/settings/company` | Update company profile |
| PUT | `/settings/profile` | Update user profile |

## Architecture Notes

- **Multi-tenancy**: Shared database with `tenant_id` column on every table. The `BelongsToTenant` trait auto-scopes all queries.
- **UUIDs**: All primary keys use UUIDs via Laravel's `HasUuids` trait.
- **Auth flow**: Sanctum token stored in `localStorage`. `AuthContext` provides `user`, `login`, `register`, `logout`, and `refreshUser`.
- **Protected routes**: `ProtectedRoute` wrapper redirects unauthenticated users to `/` (landing page).
- **Color scheme**: Persisted in `localStorage` via Mantine. Flash prevention script in `index.html`.
