# MoBilling UI

Frontend for **MoBilling** — a multi-tenant billing and statutory management platform built with React, Vite, and Mantine.

## Tech Stack

- **React** 19 + **TypeScript**
- **Vite** 7 (build tool)
- **Mantine** v8 (UI components)
- **React Query** (server state management)
- **React Router** v7 (routing)
- **Tabler Icons** (icon library)
- **Day.js** (date handling)
- **Recharts** (dashboard charts)

## Features

### Billing Module
- Client management (CRUD)
- Products & Services catalog
- Document workflow: Quotations -> Proforma Invoices -> Invoices
- Payments In (recording, receipts, email/SMS notifications)
- Client subscriptions with next-bill scheduling

### Statutory Module
- **Obligations** — register and manage recurring statutory obligations
- **Schedule** — dashboard with stat cards (total, overdue, due soon, paid), filter tabs, progress bars
- **Bills** — auto-generated from obligations, manual creation also supported
- **Categories** — hierarchical bill category management
- **Payment History** — track all payments out

### Platform
- Dashboard with revenue charts, invoice breakdown, top clients, subscription stats
- Urgent obligations widget on dashboard
- Team management
- Company settings and email templates
- SMS package purchasing
- Tenant subscription management
- Super Admin panel (tenants, plans, currencies, SMS, platform settings)
- Dark/light mode toggle
- Responsive sidebar navigation

## Project Structure

```
src/
  api/            # API client functions and TypeScript interfaces
  components/     # Reusable components organized by feature
    Dashboard/    # Dashboard widgets (charts, stats, tables)
    Layout/       # AppShell, AdminShell, ProtectedRoute
    Statutory/    # BillForm, BillTable, PaymentOutForm, StatutoryForm
  context/        # AuthContext (Sanctum auth + tenant state)
  pages/          # Route-level page components
    admin/        # Super Admin pages
  utils/          # Helpers (formatCurrency, formatDate)
```

## Local Development

```bash
# Install dependencies
npm install

# Start dev server (connects to API at localhost:8000)
npm run dev

# Type check
npx tsc --noEmit

# Production build
npm run build
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `VITE_API_URL` | `http://localhost:8000/api` | Backend API base URL |

Create `.env` file for production:
```
VITE_API_URL=https://api.yourdomain.com/api
```

## Build Output

Production build outputs to `dist/` directory, ready for static hosting (Nginx, Apache, Vercel, etc.).
