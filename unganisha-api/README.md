# MoBilling API

Backend API for **MoBilling** — a multi-tenant billing and statutory management platform built with Laravel 12.

## Tech Stack

- **PHP** 8.3+ / **Laravel** 12
- **MySQL** 8.0+
- **Sanctum** token-based authentication
- **UUID** primary keys on all tables
- Multi-tenant architecture (shared DB with `tenant_id` scoping)

## Features

### Billing
- Client management
- Products & Services catalog
- Document lifecycle: Quotation -> Proforma -> Invoice
- Payments In (with receipt uploads, email/SMS notifications)
- Client subscriptions with recurring billing (Next Bills)

### Statutory
- **Statutory Obligations** — register recurring obligations (monthly, quarterly, semi-annual, yearly, or one-time)
- **Automatic bill generation** — first bill created on registration, next bill auto-created when current is fully paid
- **Bill Categories** — hierarchical parent/child category system
- **Payments Out** — track payments against statutory bills with receipt uploads
- **Schedule dashboard** — stat cards, status tracking, days countdown
- **Safety-net cron** — `bills:generate-recurring` catches missed bill generations daily

### Platform
- Super Admin panel (tenant management, subscription plans, SMS packages, currencies)
- SMS integration (reseller gateway)
- Pesapal payment gateway for subscription payments
- Email notifications with customizable templates
- Dashboard with charts and analytics

## Database Tables

`tenants`, `users`, `clients`, `product_services`, `documents`, `document_items`, `payments_in`, `bills`, `payments_out`, `bill_categories`, `statutories`, `client_subscriptions`, `tenant_subscriptions`, `subscription_plans`, `sms_packages`, `sms_purchases`, `currencies`, `notifications`

## Key API Endpoints

### Auth
- `POST /api/auth/register` — Register tenant
- `POST /api/auth/login` — Login
- `GET /api/auth/me` — Current user

### Statutory (tenant-scoped)
- `GET|POST /api/statutories` — List/create obligations
- `GET|PUT|DELETE /api/statutories/{id}` — Show/update/delete
- `GET /api/statutory-schedule` — Schedule dashboard (stat cards + status data)
- `GET|POST /api/bills` — List/create bills
- `POST /api/payments-out` — Record payment (auto-generates next bill if statutory is fully paid)

### Billing (tenant-scoped)
- `CRUD /api/clients`
- `CRUD /api/product-services`
- `CRUD /api/documents` + convert/PDF/send
- `CRUD /api/payments-in`
- `CRUD /api/client-subscriptions`
- `GET /api/dashboard/summary`

## Scheduled Commands

| Command | Schedule | Purpose |
|---------|----------|---------|
| `bills:generate-recurring` | Daily 09:00 | Safety-net: generate bills for overdue statutory obligations |
| `bills:send-reminders` | Daily 08:00 | Email/SMS reminders for upcoming bills |
| `invoices:process-recurring` | Daily 07:00 | Generate recurring invoices from client subscriptions |
| `subscriptions:expire` | Hourly | Expire overdue tenant subscriptions |

## Local Development

```bash
# Install dependencies
composer install

# Configure environment
cp .env.example .env   # Then edit DB credentials
php artisan key:generate

# Run migrations
php artisan migrate

# Start development server
php artisan serve
```

## Environment Variables

See `DEPLOYMENT.md` for the full environment configuration reference.
