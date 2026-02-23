# Unganisha — Billing & Statutory System

> **"Your Billing, Connected."**

## Overview

**Unganisha** is a simple multi-tenant system with two core modules:

- **Billing** — Create quotations, proforma, invoices and track payments from clients
- **Statutory** — Track your recurring bills, get reminders, mark as paid

---

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | React + Mantine UI (https://mantine.dev/) |
| Backend | Laravel 11 (PHP) |
| Database | PostgreSQL |
| Auth | Laravel Sanctum (API tokens) |
| PDF | Laravel DomPDF / Snappy |
| Email | Laravel Mail (SendGrid / AWS SES / SMTP) |
| SMS | Twilio / MSG91 (via Laravel Notification) |
| Queue | Laravel Queue (Redis / Database driver) |
| Storage | Laravel Storage (S3 / local for PDFs & uploads) |
| API | RESTful JSON API (Laravel API Resources) |

---

## Project Structure

### Backend (Laravel)

```
unganisha-api/
├── app/
│   ├── Http/
│   │   ├── Controllers/
│   │   │   ├── Auth/
│   │   │   │   ├── RegisterController.php
│   │   │   │   ├── LoginController.php
│   │   │   │   └── ForgotPasswordController.php
│   │   │   ├── TenantController.php
│   │   │   ├── UserController.php
│   │   │   ├── ClientController.php
│   │   │   ├── ProductServiceController.php
│   │   │   ├── DocumentController.php
│   │   │   ├── PaymentInController.php
│   │   │   ├── BillController.php
│   │   │   ├── PaymentOutController.php
│   │   │   └── DashboardController.php
│   │   ├── Middleware/
│   │   │   └── TenantMiddleware.php
│   │   ├── Requests/
│   │   │   ├── StoreClientRequest.php
│   │   │   ├── StoreProductServiceRequest.php
│   │   │   ├── StoreDocumentRequest.php
│   │   │   ├── StoreBillRequest.php
│   │   │   └── ...
│   │   └── Resources/
│   │       ├── ClientResource.php
│   │       ├── ProductServiceResource.php
│   │       ├── DocumentResource.php
│   │       ├── BillResource.php
│   │       └── ...
│   ├── Models/
│   │   ├── Tenant.php
│   │   ├── User.php
│   │   ├── Client.php
│   │   ├── ProductService.php
│   │   ├── Document.php
│   │   ├── DocumentItem.php
│   │   ├── PaymentIn.php
│   │   ├── Bill.php
│   │   └── PaymentOut.php
│   ├── Notifications/
│   │   ├── InvoiceSentNotification.php
│   │   ├── PaymentReceivedNotification.php
│   │   ├── BillDueReminderNotification.php
│   │   └── BillOverdueNotification.php
│   ├── Services/
│   │   ├── DocumentNumberService.php
│   │   ├── DocumentConversionService.php
│   │   ├── PdfService.php
│   │   └── BillReminderService.php
│   ├── Traits/
│   │   └── BelongsToTenant.php
│   └── Console/
│       └── Commands/
│           └── SendBillReminders.php
├── database/
│   ├── migrations/
│   └── seeders/
├── routes/
│   └── api.php
└── config/
```

### Frontend (React + Mantine)

```
unganisha-ui/
├── src/
│   ├── api/
│   │   ├── axios.ts
│   │   ├── auth.ts
│   │   ├── clients.ts
│   │   ├── productServices.ts
│   │   ├── documents.ts
│   │   ├── payments.ts
│   │   ├── bills.ts
│   │   └── dashboard.ts
│   ├── components/
│   │   ├── Layout/
│   │   │   ├── AppShell.tsx         (Mantine AppShell)
│   │   │   ├── Sidebar.tsx          (Mantine NavLink)
│   │   │   └── Header.tsx           (Mantine Header)
│   │   ├── Billing/
│   │   │   ├── ClientForm.tsx       (Mantine TextInput, Select)
│   │   │   ├── ClientTable.tsx      (Mantine Table)
│   │   │   ├── ProductServiceForm.tsx
│   │   │   ├── ProductServiceTable.tsx
│   │   │   ├── DocumentForm.tsx     (Mantine form with line items)
│   │   │   ├── DocumentTable.tsx    (Mantine Table with Badge for status)
│   │   │   ├── DocumentView.tsx     (Mantine Card for document preview)
│   │   │   └── PaymentForm.tsx
│   │   ├── Statutory/
│   │   │   ├── BillForm.tsx
│   │   │   ├── BillTable.tsx
│   │   │   └── PaymentOutForm.tsx
│   │   └── Dashboard/
│   │       ├── StatsCards.tsx       (Mantine SimpleGrid + Card)
│   │       ├── RecentInvoices.tsx
│   │       └── UpcomingBills.tsx
│   ├── pages/
│   │   ├── Login.tsx
│   │   ├── Register.tsx
│   │   ├── Dashboard.tsx
│   │   ├── Clients.tsx
│   │   ├── ProductServices.tsx
│   │   ├── Quotations.tsx
│   │   ├── Proformas.tsx
│   │   ├── Invoices.tsx
│   │   ├── Bills.tsx
│   │   └── Settings.tsx
│   ├── hooks/
│   │   ├── useAuth.ts
│   │   └── useTenant.ts
│   ├── context/
│   │   └── AuthContext.tsx
│   ├── utils/
│   │   ├── formatCurrency.ts
│   │   └── formatDate.ts
│   └── App.tsx
├── package.json
└── vite.config.ts
```

---

## Multi-Tenant Strategy

- **Shared database** with `tenant_id` on every table
- Laravel middleware extracts `tenant_id` from authenticated user
- Use a `BelongsToTenant` trait on all models to auto-scope queries
- Never trust client input for `tenant_id`

### BelongsToTenant Trait

```php
// app/Traits/BelongsToTenant.php

trait BelongsToTenant
{
    protected static function bootBelongsToTenant()
    {
        static::creating(function ($model) {
            $model->tenant_id = auth()->user()->tenant_id;
        });

        static::addGlobalScope('tenant', function ($query) {
            if (auth()->check()) {
                $query->where('tenant_id', auth()->user()->tenant_id);
            }
        });
    }

    public function tenant()
    {
        return $this->belongsTo(Tenant::class);
    }
}
```

### TenantMiddleware

```php
// app/Http/Middleware/TenantMiddleware.php

class TenantMiddleware
{
    public function handle($request, Closure $next)
    {
        if (!auth()->check() || !auth()->user()->tenant_id) {
            return response()->json(['message' => 'Tenant not found'], 403);
        }
        return $next($request);
    }
}
```

---

## User Roles

| Role | Access |
|---|---|
| Admin | Full access — manage users, settings, all data |
| User | Create/edit documents, bills, payments |

---

## Database Migrations

### 1. tenants

```php
Schema::create('tenants', function (Blueprint $table) {
    $table->uuid('id')->primary();
    $table->string('name');
    $table->string('email');
    $table->string('phone')->nullable();
    $table->text('address')->nullable();
    $table->string('logo_url')->nullable();
    $table->string('tax_id')->nullable();
    $table->string('currency', 10)->default('USD');
    $table->timestamps();
    $table->softDeletes();
});
```

### 2. users

```php
Schema::create('users', function (Blueprint $table) {
    $table->uuid('id')->primary();
    $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
    $table->string('name');
    $table->string('email')->unique();
    $table->string('password');
    $table->string('phone')->nullable();
    $table->enum('role', ['admin', 'user'])->default('user');
    $table->boolean('is_active')->default(true);
    $table->rememberToken();
    $table->timestamps();
    $table->softDeletes();
});
```

### 3. clients

```php
Schema::create('clients', function (Blueprint $table) {
    $table->uuid('id')->primary();
    $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
    $table->string('name');
    $table->string('email')->nullable();
    $table->string('phone')->nullable();
    $table->text('address')->nullable();
    $table->string('tax_id')->nullable();
    $table->timestamps();
    $table->softDeletes();
});
```

### 4. product_services (Products & Services)

```php
Schema::create('product_services', function (Blueprint $table) {
    $table->uuid('id')->primary();
    $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
    $table->enum('type', ['product', 'service']);
    $table->string('name');
    $table->string('code')->nullable();           // SKU for products, service code for services
    $table->text('description')->nullable();
    $table->decimal('price', 12, 2);              // selling price or rate
    $table->decimal('tax_percent', 5, 2)->default(0);
    $table->string('unit', 20)->default('pcs');   // pcs, kg, box, hrs, days, project, etc.
    $table->string('category')->nullable();        // custom category
    $table->boolean('is_active')->default(true);
    $table->timestamps();
    $table->softDeletes();

    $table->index(['tenant_id', 'type']);
});
```

**Unit examples by type:**

| Type | Units |
|---|---|
| Product | pcs, kg, box, ltr, mtr, set, pack |
| Service | hrs, days, months, project, visit, session |

### 5. documents

```php
Schema::create('documents', function (Blueprint $table) {
    $table->uuid('id')->primary();
    $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
    $table->foreignUuid('client_id')->constrained()->cascadeOnDelete();
    $table->enum('type', ['quotation', 'proforma', 'invoice']);
    $table->string('document_number')->unique();
    $table->foreignUuid('parent_id')->nullable()->constrained('documents')->nullOnDelete();
    $table->date('date');
    $table->date('due_date')->nullable();
    $table->decimal('subtotal', 12, 2)->default(0);
    $table->decimal('tax_amount', 12, 2)->default(0);
    $table->decimal('total', 12, 2)->default(0);
    $table->text('notes')->nullable();
    $table->enum('status', ['draft', 'sent', 'accepted', 'rejected', 'paid', 'overdue', 'partial'])->default('draft');
    $table->foreignUuid('created_by')->constrained('users')->cascadeOnDelete();
    $table->timestamps();
    $table->softDeletes();
});
```

### 6. document_items

```php
Schema::create('document_items', function (Blueprint $table) {
    $table->uuid('id')->primary();
    $table->foreignUuid('document_id')->constrained()->cascadeOnDelete();
    $table->foreignUuid('product_service_id')->nullable()->constrained('product_services')->nullOnDelete();
    $table->enum('item_type', ['product', 'service']);  // quick reference
    $table->string('description');
    $table->decimal('quantity', 10, 2);
    $table->decimal('price', 12, 2);
    $table->decimal('tax_percent', 5, 2)->default(0);
    $table->decimal('tax_amount', 12, 2)->default(0);
    $table->decimal('total', 12, 2)->default(0);
    $table->string('unit', 20)->nullable();
});
```

### 7. payments_in

```php
Schema::create('payments_in', function (Blueprint $table) {
    $table->uuid('id')->primary();
    $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
    $table->foreignUuid('document_id')->constrained()->cascadeOnDelete();
    $table->decimal('amount', 12, 2);
    $table->date('payment_date');
    $table->enum('payment_method', ['cash', 'bank', 'upi', 'card', 'other'])->default('bank');
    $table->string('reference')->nullable();
    $table->text('notes')->nullable();
    $table->timestamps();
});
```

### 8. bills

```php
Schema::create('bills', function (Blueprint $table) {
    $table->uuid('id')->primary();
    $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
    $table->string('name');
    $table->string('category')->default('other');
    $table->decimal('amount', 12, 2);
    $table->enum('cycle', ['monthly', 'quarterly', 'half_yearly', 'yearly']);
    $table->date('due_date');
    $table->integer('remind_days_before')->default(3);
    $table->boolean('is_active')->default(true);
    $table->text('notes')->nullable();
    $table->timestamps();
    $table->softDeletes();
});
```

### 9. payments_out

```php
Schema::create('payments_out', function (Blueprint $table) {
    $table->uuid('id')->primary();
    $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
    $table->foreignUuid('bill_id')->constrained()->cascadeOnDelete();
    $table->decimal('amount', 12, 2);
    $table->date('payment_date');
    $table->enum('payment_method', ['cash', 'bank', 'upi', 'card', 'other'])->default('bank');
    $table->string('reference')->nullable();
    $table->text('notes')->nullable();
    $table->timestamps();
});
```

---

## Laravel API Routes

```php
// routes/api.php

// Auth (Public)
Route::post('/auth/register', [RegisterController::class, 'register']);
Route::post('/auth/login', [LoginController::class, 'login']);
Route::post('/auth/forgot-password', [ForgotPasswordController::class, 'sendResetLink']);
Route::post('/auth/reset-password', [ForgotPasswordController::class, 'reset']);

// Protected Routes
Route::middleware(['auth:sanctum', 'tenant'])->group(function () {

    // Auth
    Route::post('/auth/logout', [LoginController::class, 'logout']);
    Route::get('/auth/me', [LoginController::class, 'me']);

    // Tenant
    Route::get('/tenant', [TenantController::class, 'show']);
    Route::put('/tenant', [TenantController::class, 'update']);

    // Users (Admin only)
    Route::apiResource('users', UserController::class);

    // Clients
    Route::apiResource('clients', ClientController::class);

    // Products & Services
    Route::apiResource('product-services', ProductServiceController::class);
    Route::get('/products', [ProductServiceController::class, 'products']);    // filter type=product
    Route::get('/services', [ProductServiceController::class, 'services']);    // filter type=service

    // Documents
    Route::apiResource('documents', DocumentController::class);
    Route::post('/documents/{document}/convert', [DocumentController::class, 'convert']);
    Route::get('/documents/{document}/pdf', [DocumentController::class, 'downloadPdf']);
    Route::post('/documents/{document}/send', [DocumentController::class, 'send']);

    // Payments In
    Route::apiResource('payments-in', PaymentInController::class)->only(['index', 'store', 'show']);

    // Bills (Statutory)
    Route::apiResource('bills', BillController::class);

    // Payments Out
    Route::apiResource('payments-out', PaymentOutController::class)->only(['index', 'store', 'show']);

    // Dashboard
    Route::get('/dashboard/summary', [DashboardController::class, 'summary']);
});
```

---

## Laravel Models

### ProductService Model

```php
// app/Models/ProductService.php

class ProductService extends Model
{
    use HasFactory, SoftDeletes, BelongsToTenant;
    use HasUuids;

    protected $table = 'product_services';

    protected $fillable = [
        'tenant_id', 'type', 'name', 'code', 'description',
        'price', 'tax_percent', 'unit', 'category', 'is_active',
    ];

    protected $casts = [
        'price' => 'decimal:2',
        'tax_percent' => 'decimal:2',
        'is_active' => 'boolean',
    ];

    // Scopes
    public function scopeProducts($query)
    {
        return $query->where('type', 'product');
    }

    public function scopeServices($query)
    {
        return $query->where('type', 'service');
    }

    public function scopeActive($query)
    {
        return $query->where('is_active', true);
    }
}
```

### Document Model

```php
// app/Models/Document.php

class Document extends Model
{
    use HasFactory, SoftDeletes, BelongsToTenant;
    use HasUuids;

    protected $fillable = [
        'tenant_id', 'client_id', 'type', 'document_number',
        'parent_id', 'date', 'due_date', 'subtotal', 'tax_amount',
        'total', 'notes', 'status', 'created_by',
    ];

    protected $casts = [
        'date' => 'date',
        'due_date' => 'date',
        'subtotal' => 'decimal:2',
        'tax_amount' => 'decimal:2',
        'total' => 'decimal:2',
    ];

    public function client()
    {
        return $this->belongsTo(Client::class);
    }

    public function items()
    {
        return $this->hasMany(DocumentItem::class);
    }

    public function payments()
    {
        return $this->hasMany(PaymentIn::class);
    }

    public function parent()
    {
        return $this->belongsTo(Document::class, 'parent_id');
    }

    public function children()
    {
        return $this->hasMany(Document::class, 'parent_id');
    }

    public function createdBy()
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function getPaidAmountAttribute()
    {
        return $this->payments()->sum('amount');
    }

    public function getBalanceDueAttribute()
    {
        return $this->total - $this->paid_amount;
    }
}
```

### DocumentItem Model

```php
// app/Models/DocumentItem.php

class DocumentItem extends Model
{
    use HasFactory, HasUuids;

    public $timestamps = false;

    protected $fillable = [
        'document_id', 'product_service_id', 'item_type',
        'description', 'quantity', 'price', 'tax_percent',
        'tax_amount', 'total', 'unit',
    ];

    protected $casts = [
        'quantity' => 'decimal:2',
        'price' => 'decimal:2',
        'tax_percent' => 'decimal:2',
        'tax_amount' => 'decimal:2',
        'total' => 'decimal:2',
    ];

    public function document()
    {
        return $this->belongsTo(Document::class);
    }

    public function productService()
    {
        return $this->belongsTo(ProductService::class);
    }
}
```

### Bill Model

```php
// app/Models/Bill.php

class Bill extends Model
{
    use HasFactory, SoftDeletes, BelongsToTenant;
    use HasUuids;

    protected $fillable = [
        'tenant_id', 'name', 'category', 'amount',
        'cycle', 'due_date', 'remind_days_before',
        'is_active', 'notes',
    ];

    protected $casts = [
        'due_date' => 'date',
        'amount' => 'decimal:2',
        'is_active' => 'boolean',
    ];

    public function payments()
    {
        return $this->hasMany(PaymentOut::class);
    }

    public function getNextDueDateAttribute()
    {
        return match ($this->cycle) {
            'monthly' => $this->due_date->addMonth(),
            'quarterly' => $this->due_date->addMonths(3),
            'half_yearly' => $this->due_date->addMonths(6),
            'yearly' => $this->due_date->addYear(),
        };
    }
}
```

---

## Key Laravel Services

### DocumentNumberService

```php
// app/Services/DocumentNumberService.php

class DocumentNumberService
{
    public function generate(string $type, string $tenantId): string
    {
        $prefix = match ($type) {
            'quotation' => 'QUO',
            'proforma' => 'PRO',
            'invoice' => 'INV',
        };

        $year = now()->format('Y');

        $lastNumber = Document::withoutGlobalScopes()
            ->where('tenant_id', $tenantId)
            ->where('type', $type)
            ->whereYear('created_at', $year)
            ->count();

        $sequence = str_pad($lastNumber + 1, 4, '0', STR_PAD_LEFT);

        return "{$prefix}-{$year}-{$sequence}";
    }
}
```

### DocumentConversionService

```php
// app/Services/DocumentConversionService.php

class DocumentConversionService
{
    public function convert(Document $document, string $targetType): Document
    {
        $allowedConversions = [
            'quotation' => 'proforma',
            'proforma' => 'invoice',
        ];

        if ($allowedConversions[$document->type] !== $targetType) {
            throw new \Exception("Cannot convert {$document->type} to {$targetType}");
        }

        $newDocument = $document->replicate();
        $newDocument->type = $targetType;
        $newDocument->parent_id = $document->id;
        $newDocument->status = 'draft';
        $newDocument->document_number = app(DocumentNumberService::class)
            ->generate($targetType, $document->tenant_id);
        $newDocument->save();

        // Copy line items
        foreach ($document->items as $item) {
            $newItem = $item->replicate();
            $newItem->document_id = $newDocument->id;
            $newItem->save();
        }

        // Update original status
        $document->update(['status' => 'accepted']);

        return $newDocument;
    }
}
```

### ProductServiceController

```php
// app/Http/Controllers/ProductServiceController.php

class ProductServiceController extends Controller
{
    public function index(Request $request)
    {
        $query = ProductService::query();

        // Filter by type
        if ($request->has('type')) {
            $query->where('type', $request->type);
        }

        // Search
        if ($request->has('search')) {
            $query->where(function ($q) use ($request) {
                $q->where('name', 'ilike', "%{$request->search}%")
                  ->orWhere('code', 'ilike', "%{$request->search}%");
            });
        }

        // Filter active only
        if ($request->boolean('active_only', false)) {
            $query->active();
        }

        return ProductServiceResource::collection(
            $query->orderBy('name')->paginate($request->per_page ?? 20)
        );
    }

    public function store(StoreProductServiceRequest $request)
    {
        $productService = ProductService::create($request->validated());
        return new ProductServiceResource($productService);
    }

    public function show(ProductService $productService)
    {
        return new ProductServiceResource($productService);
    }

    public function update(StoreProductServiceRequest $request, ProductService $productService)
    {
        $productService->update($request->validated());
        return new ProductServiceResource($productService);
    }

    public function destroy(ProductService $productService)
    {
        $productService->delete();
        return response()->json(['message' => 'Deleted successfully']);
    }

    // Shortcut: GET /api/products
    public function products(Request $request)
    {
        $request->merge(['type' => 'product']);
        return $this->index($request);
    }

    // Shortcut: GET /api/services
    public function services(Request $request)
    {
        $request->merge(['type' => 'service']);
        return $this->index($request);
    }
}
```

### Bill Reminder Command

```php
// app/Console/Commands/SendBillReminders.php

class SendBillReminders extends Command
{
    protected $signature = 'bills:send-reminders';
    protected $description = 'Send reminders for upcoming bills';

    public function handle()
    {
        $bills = Bill::withoutGlobalScopes()
            ->where('is_active', true)
            ->whereRaw("due_date - (remind_days_before || ' days')::interval <= CURRENT_DATE")
            ->where('due_date', '>=', now()->toDateString())
            ->get();

        foreach ($bills as $bill) {
            $users = User::where('tenant_id', $bill->tenant_id)->get();
            foreach ($users as $user) {
                $user->notify(new BillDueReminderNotification($bill));
            }
        }

        $this->info("Sent reminders for {$bills->count()} bills.");
    }
}

// Schedule in routes/console.php (Laravel 11)
Schedule::command('bills:send-reminders')->dailyAt('08:00');
```

---

## Laravel Notifications

### Invoice Sent Notification

```php
// app/Notifications/InvoiceSentNotification.php

class InvoiceSentNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(public Document $document) {}

    public function via($notifiable): array
    {
        return ['mail'];  // Add SMS channel when configured
    }

    public function toMail($notifiable): MailMessage
    {
        return (new MailMessage)
            ->subject("Invoice {$this->document->document_number} — Unganisha")
            ->greeting("Hello {$this->document->client->name},")
            ->line("You have a new invoice of {$this->document->total}.")
            ->line("Due date: {$this->document->due_date->format('d M Y')}")
            ->action('View Invoice', url("/invoices/{$this->document->id}"))
            ->line('Thank you for your business.');
    }
}
```

### Bill Due Reminder Notification

```php
// app/Notifications/BillDueReminderNotification.php

class BillDueReminderNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(public Bill $bill) {}

    public function via($notifiable): array
    {
        return ['mail'];  // Add SMS channel when configured
    }

    public function toMail($notifiable): MailMessage
    {
        return (new MailMessage)
            ->subject("Bill Reminder: {$this->bill->name} — Unganisha")
            ->line("{$this->bill->name} of {$this->bill->amount} is due on {$this->bill->due_date->format('d M Y')}.")
            ->line("Don't forget to pay!")
            ->action('View Bills', url('/bills'));
    }
}
```

---

## Frontend — Mantine UI

### Package Setup

```bash
npm create vite@latest unganisha-ui -- --template react-ts
cd unganisha-ui
npm install @mantine/core @mantine/hooks @mantine/form @mantine/dates
npm install @mantine/notifications @mantine/modals
npm install @tabler/icons-react
npm install axios react-router-dom dayjs
npm install @tanstack/react-query
npm install postcss postcss-preset-mantine postcss-simple-vars
```

### Mantine Provider Setup

```tsx
// src/App.tsx

import { MantineProvider } from '@mantine/core';
import { Notifications } from '@mantine/notifications';
import { ModalsProvider } from '@mantine/modals';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { BrowserRouter } from 'react-router-dom';
import '@mantine/core/styles.css';
import '@mantine/dates/styles.css';
import '@mantine/notifications/styles.css';

const queryClient = new QueryClient();

export default function App() {
  return (
    <MantineProvider defaultColorScheme="light">
      <Notifications position="top-right" />
      <ModalsProvider>
        <QueryClientProvider client={queryClient}>
          <BrowserRouter>
            {/* Routes here */}
          </BrowserRouter>
        </QueryClientProvider>
      </ModalsProvider>
    </MantineProvider>
  );
}
```

### Axios Setup

```ts
// src/api/axios.ts

import axios from 'axios';

const api = axios.create({
  baseURL: import.meta.env.VITE_API_URL || 'http://localhost:8000/api',
  headers: { 'Content-Type': 'application/json' },
});

api.interceptors.request.use((config) => {
  const token = localStorage.getItem('token');
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});

api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      localStorage.removeItem('token');
      window.location.href = '/login';
    }
    return Promise.reject(error);
  }
);

export default api;
```

### Mantine Components Used Per Page

| Page | Mantine Components |
|---|---|
| **Layout** | AppShell, NavLink, Burger, Avatar, Menu |
| **Login/Register** | TextInput, PasswordInput, Button, Paper, Stack |
| **Dashboard** | SimpleGrid, Card, Text, Badge, Table, Progress |
| **Client List** | Table, TextInput (search), Button, ActionIcon, Modal |
| **Client Form** | TextInput, Textarea, Button, Group |
| **Products & Services** | Table, Badge (product/service), Tabs (All/Products/Services), Switch (active) |
| **Product/Service Form** | SegmentedControl (type), TextInput, NumberInput, Select (unit/category), Textarea |
| **Document List** | Table, Badge (status), Menu (actions), Tabs (type filter) |
| **Document Form** | Select (client), Table (line items with product/service select), NumberInput, Textarea, DateInput |
| **Document View** | Card, Group, Text, Divider, Table, Badge, Button (convert/send/pdf) |
| **Bill List** | Table, Badge (due/overdue/paid), Switch (active) |
| **Bill Form** | TextInput, NumberInput, Select (cycle/category), DateInput |
| **Settings** | TextInput, Textarea, FileInput (logo), Tabs |
| **Notifications** | Notifications system (@mantine/notifications) |

### App Shell Layout

```tsx
// src/components/Layout/AppShell.tsx

import { AppShell, NavLink, Group, Text, Avatar } from '@mantine/core';
import {
  IconDashboard, IconUsers, IconPackages,
  IconFileText, IconFileInvoice, IconReceipt,
  IconCalendarDue, IconSettings,
} from '@tabler/icons-react';

export function AppLayout({ children }) {
  return (
    <AppShell
      navbar={{ width: 250, breakpoint: 'sm' }}
      header={{ height: 60 }}
      padding="md"
    >
      <AppShell.Header>
        <Group h="100%" px="md" justify="space-between">
          <Text size="lg" fw={700}>Unganisha</Text>
          <Avatar radius="xl" />
        </Group>
      </AppShell.Header>

      <AppShell.Navbar p="md">
        <NavLink label="Dashboard" leftSection={<IconDashboard size={18} />} href="/" />

        <NavLink label="Billing" leftSection={<IconFileText size={18} />} defaultOpened>
          <NavLink label="Clients" leftSection={<IconUsers size={16} />} href="/clients" />
          <NavLink label="Products & Services" leftSection={<IconPackages size={16} />} href="/product-services" />
          <NavLink label="Quotations" href="/quotations" />
          <NavLink label="Proforma" href="/proformas" />
          <NavLink label="Invoices" leftSection={<IconFileInvoice size={16} />} href="/invoices" />
        </NavLink>

        <NavLink label="Statutory" leftSection={<IconCalendarDue size={18} />} defaultOpened>
          <NavLink label="Bills" href="/bills" />
          <NavLink label="Payment History" leftSection={<IconReceipt size={16} />} href="/payments-out" />
        </NavLink>

        <NavLink label="Settings" leftSection={<IconSettings size={18} />} href="/settings" />
      </AppShell.Navbar>

      <AppShell.Main>{children}</AppShell.Main>
    </AppShell>
  );
}
```

### Products & Services Page

```tsx
// src/pages/ProductServices.tsx

import { useState } from 'react';
import {
  Table, Badge, Button, Group, TextInput, Tabs,
  ActionIcon, Modal, Switch, Text
} from '@mantine/core';
import { IconPlus, IconEdit, IconTrash, IconSearch } from '@tabler/icons-react';

export function ProductServicesPage({ data }) {
  const [activeTab, setActiveTab] = useState('all');

  const filtered = activeTab === 'all'
    ? data
    : data.filter(item => item.type === activeTab);

  return (
    <>
      <Group justify="space-between" mb="md">
        <Text size="xl" fw={700}>Products & Services</Text>
        <Button leftSection={<IconPlus size={16} />}>Add New</Button>
      </Group>

      <Group mb="md">
        <TextInput placeholder="Search..." leftSection={<IconSearch size={16} />} />
        <Tabs value={activeTab} onChange={setActiveTab}>
          <Tabs.List>
            <Tabs.Tab value="all">All</Tabs.Tab>
            <Tabs.Tab value="product">Products</Tabs.Tab>
            <Tabs.Tab value="service">Services</Tabs.Tab>
          </Tabs.List>
        </Tabs>
      </Group>

      <Table striped highlightOnHover>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Type</Table.Th>
            <Table.Th>Code</Table.Th>
            <Table.Th>Name</Table.Th>
            <Table.Th>Price</Table.Th>
            <Table.Th>Tax %</Table.Th>
            <Table.Th>Unit</Table.Th>
            <Table.Th>Active</Table.Th>
            <Table.Th>Actions</Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {filtered.map((item) => (
            <Table.Tr key={item.id}>
              <Table.Td>
                <Badge color={item.type === 'product' ? 'blue' : 'green'}>
                  {item.type}
                </Badge>
              </Table.Td>
              <Table.Td>{item.code}</Table.Td>
              <Table.Td>{item.name}</Table.Td>
              <Table.Td>{item.price}</Table.Td>
              <Table.Td>{item.tax_percent}%</Table.Td>
              <Table.Td>{item.unit}</Table.Td>
              <Table.Td><Switch checked={item.is_active} readOnly /></Table.Td>
              <Table.Td>
                <Group gap="xs">
                  <ActionIcon variant="light"><IconEdit size={16} /></ActionIcon>
                  <ActionIcon variant="light" color="red"><IconTrash size={16} /></ActionIcon>
                </Group>
              </Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
    </>
  );
}
```

### Product/Service Form

```tsx
// src/components/Billing/ProductServiceForm.tsx

import { useForm } from '@mantine/form';
import {
  TextInput, NumberInput, Select, Textarea,
  Button, Group, SegmentedControl, Switch
} from '@mantine/core';

export function ProductServiceForm({ onSubmit, initialValues }) {
  const form = useForm({
    initialValues: initialValues || {
      type: 'product',
      name: '',
      code: '',
      description: '',
      price: 0,
      tax_percent: 0,
      unit: 'pcs',
      category: '',
      is_active: true,
    },
  });

  const unitOptions = form.values.type === 'product'
    ? [
        { value: 'pcs', label: 'Pieces' },
        { value: 'kg', label: 'Kilograms' },
        { value: 'box', label: 'Box' },
        { value: 'ltr', label: 'Litres' },
        { value: 'mtr', label: 'Metres' },
        { value: 'set', label: 'Set' },
        { value: 'pack', label: 'Pack' },
      ]
    : [
        { value: 'hrs', label: 'Hours' },
        { value: 'days', label: 'Days' },
        { value: 'months', label: 'Months' },
        { value: 'project', label: 'Project' },
        { value: 'visit', label: 'Visit' },
        { value: 'session', label: 'Session' },
      ];

  return (
    <form onSubmit={form.onSubmit(onSubmit)}>
      <SegmentedControl
        fullWidth
        data={[
          { value: 'product', label: 'Product' },
          { value: 'service', label: 'Service' },
        ]}
        {...form.getInputProps('type')}
        mb="md"
      />

      <TextInput label="Name" placeholder="e.g., Laptop / Consulting" required
        {...form.getInputProps('name')} />

      <TextInput label="Code" placeholder="e.g., SKU-001 / SRV-001" mt="md"
        {...form.getInputProps('code')} />

      <Textarea label="Description" mt="md"
        {...form.getInputProps('description')} />

      <Group grow mt="md">
        <NumberInput label="Price / Rate" min={0} decimalScale={2} required
          {...form.getInputProps('price')} />
        <NumberInput label="Tax %" min={0} max={100} decimalScale={2}
          {...form.getInputProps('tax_percent')} />
      </Group>

      <Group grow mt="md">
        <Select label="Unit" data={unitOptions}
          {...form.getInputProps('unit')} />
        <TextInput label="Category" placeholder="e.g., Electronics, IT Services"
          {...form.getInputProps('category')} />
      </Group>

      <Switch label="Active" mt="md"
        {...form.getInputProps('is_active', { type: 'checkbox' })} />

      <Group justify="flex-end" mt="xl">
        <Button type="submit">Save</Button>
      </Group>
    </form>
  );
}
```

### Document Form (Updated with Products & Services)

```tsx
// src/components/Billing/DocumentForm.tsx

import { useForm } from '@mantine/form';
import {
  Select, NumberInput, Textarea,
  Table, Button, Group, ActionIcon, Badge
} from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { IconPlus, IconTrash } from '@tabler/icons-react';

export function DocumentForm({ clients, productServices, type, onSubmit }) {
  const form = useForm({
    initialValues: {
      client_id: '',
      date: new Date(),
      due_date: null,
      notes: '',
      items: [{ product_service_id: '', quantity: 1, price: 0, tax_percent: 0 }],
    },
  });

  // When product/service is selected, auto-fill price, tax, unit
  const handleItemSelect = (index: number, productServiceId: string) => {
    const selected = productServices.find(ps => ps.id === productServiceId);
    if (selected) {
      form.setFieldValue(`items.${index}.product_service_id`, productServiceId);
      form.setFieldValue(`items.${index}.price`, selected.price);
      form.setFieldValue(`items.${index}.tax_percent`, selected.tax_percent);
    }
  };

  const addItem = () => {
    form.insertListItem('items', {
      product_service_id: '', quantity: 1, price: 0, tax_percent: 0,
    });
  };

  const removeItem = (index: number) => {
    form.removeListItem('items', index);
  };

  return (
    <form onSubmit={form.onSubmit(onSubmit)}>
      <Select
        label="Client"
        placeholder="Select client"
        data={clients.map(c => ({ value: c.id, label: c.name }))}
        {...form.getInputProps('client_id')}
        searchable
      />

      <Group grow mt="md">
        <DateInput label="Date" {...form.getInputProps('date')} />
        <DateInput label="Due Date" {...form.getInputProps('due_date')} />
      </Group>

      <Table mt="md">
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Product / Service</Table.Th>
            <Table.Th>Type</Table.Th>
            <Table.Th>Qty</Table.Th>
            <Table.Th>Price</Table.Th>
            <Table.Th>Tax %</Table.Th>
            <Table.Th>Total</Table.Th>
            <Table.Th></Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {form.values.items.map((item, index) => {
            const selected = productServices.find(ps => ps.id === item.product_service_id);
            return (
              <Table.Tr key={index}>
                <Table.Td>
                  <Select
                    data={productServices.map(ps => ({
                      value: ps.id,
                      label: `${ps.name} (${ps.code || ps.type})`,
                    }))}
                    value={item.product_service_id}
                    onChange={(val) => handleItemSelect(index, val)}
                    searchable
                    placeholder="Select item"
                  />
                </Table.Td>
                <Table.Td>
                  {selected && (
                    <Badge color={selected.type === 'product' ? 'blue' : 'green'} size="sm">
                      {selected.type}
                    </Badge>
                  )}
                </Table.Td>
                <Table.Td>
                  <NumberInput min={1} {...form.getInputProps(`items.${index}.quantity`)} />
                </Table.Td>
                <Table.Td>
                  <NumberInput min={0} {...form.getInputProps(`items.${index}.price`)} />
                </Table.Td>
                <Table.Td>
                  <NumberInput min={0} {...form.getInputProps(`items.${index}.tax_percent`)} />
                </Table.Td>
                <Table.Td>
                  {(item.quantity * item.price * (1 + item.tax_percent / 100)).toFixed(2)}
                </Table.Td>
                <Table.Td>
                  <ActionIcon color="red" onClick={() => removeItem(index)}>
                    <IconTrash size={16} />
                  </ActionIcon>
                </Table.Td>
              </Table.Tr>
            );
          })}
        </Table.Tbody>
      </Table>

      <Button variant="light" leftSection={<IconPlus size={16} />} onClick={addItem} mt="sm">
        Add Item
      </Button>

      <Textarea label="Notes" mt="md" {...form.getInputProps('notes')} />

      <Group justify="flex-end" mt="xl">
        <Button type="submit">Save {type}</Button>
      </Group>
    </form>
  );
}
```

### Bill Form (Statutory)

```tsx
// src/components/Statutory/BillForm.tsx

import { useForm } from '@mantine/form';
import { TextInput, NumberInput, Select, Textarea, Button, Group, Switch } from '@mantine/core';
import { DateInput } from '@mantine/dates';

export function BillForm({ onSubmit, initialValues }) {
  const form = useForm({
    initialValues: initialValues || {
      name: '',
      category: 'other',
      amount: 0,
      cycle: 'monthly',
      due_date: new Date(),
      remind_days_before: 3,
      is_active: true,
      notes: '',
    },
  });

  return (
    <form onSubmit={form.onSubmit(onSubmit)}>
      <TextInput label="Bill Name" placeholder="e.g., Electricity" required
        {...form.getInputProps('name')} />

      <Group grow mt="md">
        <Select label="Category" data={[
          { value: 'utility', label: 'Utility' },
          { value: 'rent', label: 'Rent' },
          { value: 'subscription', label: 'Subscription' },
          { value: 'loan', label: 'Loan' },
          { value: 'insurance', label: 'Insurance' },
          { value: 'other', label: 'Other' },
        ]} {...form.getInputProps('category')} />

        <NumberInput label="Amount" min={0} decimalScale={2} required
          {...form.getInputProps('amount')} />
      </Group>

      <Group grow mt="md">
        <Select label="Billing Cycle" data={[
          { value: 'monthly', label: 'Monthly' },
          { value: 'quarterly', label: 'Quarterly' },
          { value: 'half_yearly', label: 'Half Yearly' },
          { value: 'yearly', label: 'Yearly' },
        ]} {...form.getInputProps('cycle')} />

        <DateInput label="Next Due Date" required
          {...form.getInputProps('due_date')} />
      </Group>

      <Group grow mt="md">
        <NumberInput label="Remind Days Before" min={1} max={30}
          {...form.getInputProps('remind_days_before')} />

        <Switch label="Active" mt="xl"
          {...form.getInputProps('is_active', { type: 'checkbox' })} />
      </Group>

      <Textarea label="Notes" mt="md" {...form.getInputProps('notes')} />

      <Group justify="flex-end" mt="xl">
        <Button type="submit">Save Bill</Button>
      </Group>
    </form>
  );
}
```

---

## Core Features to Build

### Billing Module

1. **Client Management** — CRUD with Mantine Table + Modal form
2. **Products & Services** — CRUD with type (product/service), filterable tabs, active toggle
3. **Quotation** — Create with product/service line items, generate PDF, send email/SMS
4. **Proforma** — Convert quotation or create standalone
5. **Invoice** — Convert proforma or create standalone, auto-number
6. **Document Conversion** — One-click convert with data carried forward
7. **Payment Recording** — Full or partial payment, auto-update invoice status
8. **PDF Generation** — Laravel DomPDF with tenant branding
9. **Send via Email/SMS** — Laravel Notification system

### Statutory Module

1. **Bill Management** — CRUD with cycle & reminder settings
2. **Payment Recording** — Mark paid, record details
3. **Auto Due Date Update** — Calculate next due date after payment
4. **Reminder Cron Job** — Daily check & send Email/SMS reminders

---

## Document Status Flow

### Quotation

```
Draft → Sent → Accepted → Converted to Proforma
                → Rejected
```

### Proforma

```
Draft → Sent → Accepted → Converted to Invoice
                → Rejected
```

### Invoice

```
Draft → Sent → Partial Payment → Paid
                → Overdue
```

### Bill (Statutory)

```
Active → Due Soon (reminder sent) → Overdue → Paid → Next Cycle
```

---

## Document Numbering

| Document | Format | Example |
|---|---|---|
| Quotation | QUO-{YEAR}-{SEQUENCE} | QUO-2026-0001 |
| Proforma | PRO-{YEAR}-{SEQUENCE} | PRO-2026-0001 |
| Invoice | INV-{YEAR}-{SEQUENCE} | INV-2026-0001 |

---

## UI Navigation (Updated)

```
Unganisha
├── Dashboard
├── Billing
│   ├── Clients
│   ├── Products & Services
│   ├── Quotations
│   ├── Proforma Invoices
│   └── Invoices
├── Statutory
│   ├── Bills
│   └── Payment History
└── Settings
    ├── Company Profile
    ├── Users
    └── Notification Settings
```

---

## Build Order

### Phase 1: Foundation

1. `composer create-project laravel/laravel unganisha-api` — Setup Laravel
2. Configure PostgreSQL in `.env`
3. `php artisan install:api` — Setup Sanctum
4. Create all migrations & run `php artisan migrate`
5. Create `BelongsToTenant` trait & `TenantMiddleware`
6. Create base models with trait applied
7. `npm create vite@latest unganisha-ui -- --template react-ts` — Setup React
8. Install Mantine packages & configure MantineProvider
9. Setup Axios API client with auth token interceptor
10. Create AppShell layout with sidebar navigation

### Phase 2: Master Data

11. Client CRUD — Laravel API Resource + Mantine Table & Modal Form
12. Products & Services CRUD — Laravel API + Mantine Tabs (All/Products/Services) + Form with SegmentedControl

### Phase 3: Billing Module

13. Document CRUD — Laravel API + Document Form with product/service line items
14. Auto-fill price & tax when product/service is selected in line item
15. Document conversion logic (quotation → proforma → invoice)
16. Payment recording — API + Mantine Form
17. PDF generation — Laravel DomPDF with Blade template
18. Send document via email — Laravel Notification + queue

### Phase 4: Statutory Module

19. Bill CRUD — Laravel API + Mantine Table & Form
20. Payment out recording — API + Mantine Form
21. Auto due date calculation after payment
22. Reminder cron job — `bills:send-reminders` artisan command
23. SMS integration (Twilio/MSG91 via Laravel Notification channel)

### Phase 5: Dashboard

24. Dashboard summary API endpoint (receivable, payable, overdue counts)
25. Dashboard page with Mantine SimpleGrid + Cards + Tables
26. Overdue alerts display

---

## Notes

- All API routes protected by Laravel Sanctum
- Every model uses `BelongsToTenant` trait for auto-scoping
- Soft delete on all main tables (`deleted_at` column)
- All amounts stored as `DECIMAL(12,2)`
- All dates stored in UTC, convert on frontend using `dayjs`
- Use Laravel Form Requests for validation
- Use Laravel API Resources for consistent JSON response
- Use `@tanstack/react-query` for frontend data fetching & caching
- Use `@mantine/notifications` for toast messages
- Use `@mantine/modals` for confirm dialogs (delete, convert)
- Use Laravel Queue for async email/SMS sending
- Schedule bill reminders via Laravel Scheduler
- Products & Services use single table with `type` field (product/service)
- Document line items reference `product_service_id` and store `item_type` for quick filtering
