import api from './axios';

export interface Tenant {
  id: string;
  name: string;
  email: string;
  phone: string | null;
  address: string | null;
  tax_id: string | null;
  currency: string;
  is_active: boolean;
  trial_ends_at: string | null;
  subscription_status?: 'trial' | 'subscribed' | 'expired' | 'deactivated';
  days_remaining?: number;
  expires_at?: string | null;
  email_enabled: boolean;
  smtp_host: string | null;
  users_count: number;
  allowed_permissions_count?: number;
  created_at: string;
}

export interface TenantFormData {
  name: string;
  email: string;
  phone: string;
  address: string;
  tax_id: string;
  currency: string;
}

export interface CreateTenantData extends TenantFormData {
  admin_name: string;
  admin_email: string;
  admin_password: string;
}

// --- Admin Dashboard ---

export interface AdminDashboard {
  total_tenants: number;
  active_tenants: number;
  sms_enabled_tenants: number;
  total_users: number;
  master_sms_balance: number | null;
  total_sms_revenue: number;
  total_sms_sold: number;
  pending_purchases: number;
  recent_purchases: {
    id: string;
    tenant_name: string | null;
    user_name: string | null;
    sms_quantity: number;
    total_amount: string;
    status: string;
    created_at: string;
  }[];
}

export const getAdminDashboard = () =>
  api.get<AdminDashboard>('/admin/dashboard');

export const getTenants = (params?: { search?: string; page?: number; per_page?: number }) =>
  api.get('/admin/tenants', { params });

export const getTenant = (id: string) =>
  api.get<{ data: Tenant }>(`/admin/tenants/${id}`);

export const createTenant = (data: CreateTenantData) =>
  api.post('/admin/tenants', data);

export const updateTenant = (id: string, data: TenantFormData) =>
  api.put(`/admin/tenants/${id}`, data);

export const toggleTenantActive = (id: string) =>
  api.patch(`/admin/tenants/${id}/toggle-active`);

export const impersonateTenant = (tenantId: string) =>
  api.post<{
    user: import('./auth').User;
    token: string;
    subscription_status?: 'trial' | 'subscribed' | 'expired' | 'deactivated';
    days_remaining?: number;
  }>(`/admin/tenants/${tenantId}/impersonate`);

// --- Tenant User Management ---

export { type TenantUser, type UserFormData } from './users';

export const getTenantUsers = (tenantId: string, params?: { search?: string; page?: number; per_page?: number }) =>
  api.get(`/admin/tenants/${tenantId}/users`, { params });

export const createTenantUser = (tenantId: string, data: import('./users').UserFormData) =>
  api.post(`/admin/tenants/${tenantId}/users`, data);

export const updateTenantUser = (tenantId: string, userId: string, data: import('./users').UserFormData) =>
  api.put(`/admin/tenants/${tenantId}/users/${userId}`, data);

export const toggleTenantUserActive = (tenantId: string, userId: string) =>
  api.patch(`/admin/tenants/${tenantId}/users/${userId}/toggle-active`);

// --- Tenant Email Settings (Super Admin) ---

export interface SmtpSettings {
  email_enabled: boolean;
  smtp_host: string | null;
  smtp_port: number | null;
  smtp_username: string | null;
  smtp_encryption: string | null;
  smtp_from_email: string | null;
  smtp_from_name: string | null;
  has_password: boolean;
}

export interface SmtpSettingsFormData {
  email_enabled: boolean;
  smtp_host: string;
  smtp_port: number | string;
  smtp_username: string;
  smtp_password: string;
  smtp_encryption: string;
  smtp_from_email: string;
  smtp_from_name: string;
}

export const getTenantEmailSettings = (tenantId: string) =>
  api.get<{ data: SmtpSettings }>(`/admin/tenants/${tenantId}/email-settings`);

export const updateTenantEmailSettings = (tenantId: string, data: Partial<SmtpSettingsFormData>) =>
  api.put<{ data: SmtpSettings }>(`/admin/tenants/${tenantId}/email-settings`, data);

export const testTenantEmailSettings = (tenantId: string) =>
  api.post<{ message: string }>(`/admin/tenants/${tenantId}/email-settings/test`);

// --- Tenant SMS Settings (Super Admin) ---

export interface SmsSettings {
  sms_enabled: boolean;
  gateway_email: string | null;
  gateway_username: string | null;
  sender_id: string | null;
  has_authorization: boolean;
  sms_balance: number | null;
  balance_error?: string;
}

export interface SmsSettingsFormData {
  sms_enabled: boolean;
  gateway_email: string;
  gateway_username: string;
  sender_id: string;
  sms_authorization: string;
}

export const getTenantSmsSettings = (tenantId: string) =>
  api.get<{ data: SmsSettings }>(`/admin/tenants/${tenantId}/sms-settings`);

export const updateTenantSmsSettings = (tenantId: string, data: Partial<SmsSettingsFormData>) =>
  api.put<{ data: SmsSettings }>(`/admin/tenants/${tenantId}/sms-settings`, data);

export const rechargeTenantSms = (tenantId: string, sms_count: number) =>
  api.post(`/admin/tenants/${tenantId}/sms-recharge`, { sms_count });

export const deductTenantSms = (tenantId: string, sms_count: number) =>
  api.post(`/admin/tenants/${tenantId}/sms-deduct`, { sms_count });

// --- Tenant Templates (Super Admin) ---

export interface TenantTemplates {
  reminder_email_subject: string | null;
  reminder_email_body: string | null;
  overdue_email_subject: string | null;
  overdue_email_body: string | null;
  reminder_sms_body: string | null;
  overdue_sms_body: string | null;
  invoice_email_subject: string | null;
  invoice_email_body: string | null;
  email_footer_text: string | null;
}

export const getTenantTemplates = (tenantId: string) =>
  api.get<{ data: TenantTemplates }>(`/admin/tenants/${tenantId}/templates`);

export const updateTenantTemplates = (tenantId: string, data: Partial<TenantTemplates>) =>
  api.put<{ data: TenantTemplates; message: string }>(`/admin/tenants/${tenantId}/templates`, data);

// --- SMS Packages (Super Admin) ---

export interface SmsPackage {
  id: string;
  name: string;
  price_per_sms: string;
  min_quantity: number;
  max_quantity: number | null;
  is_active: boolean;
  sort_order: number;
  created_at: string;
}

export interface SmsPackageFormData {
  name: string;
  price_per_sms: number | string;
  min_quantity: number | string;
  max_quantity: number | string | null;
  is_active: boolean;
  sort_order: number | string;
}

export const getSmsPackages = () =>
  api.get<{ data: SmsPackage[] }>('/admin/sms-packages');

export const createSmsPackage = (data: SmsPackageFormData) =>
  api.post<{ data: SmsPackage }>('/admin/sms-packages', data);

export const updateSmsPackage = (id: string, data: SmsPackageFormData) =>
  api.put<{ data: SmsPackage }>(`/admin/sms-packages/${id}`, data);

export const deleteSmsPackage = (id: string) =>
  api.delete(`/admin/sms-packages/${id}`);

// --- Subscription Plans (Super Admin) ---

export interface SubscriptionPlanAdmin {
  id: string;
  name: string;
  slug: string;
  description: string | null;
  price: string;
  billing_cycle_days: number;
  features: string[] | null;
  is_active: boolean;
  sort_order: number;
  permissions_count?: number;
  permissions?: { id: string }[];
  created_at: string;
}

export interface SubscriptionPlanFormData {
  name: string;
  slug: string;
  description: string;
  price: number | string;
  billing_cycle_days: number | string;
  features: string[];
  is_active: boolean;
  sort_order: number | string;
  permission_ids: string[];
}

export const getAdminSubscriptionPlans = () =>
  api.get<{ data: SubscriptionPlanAdmin[] }>('/admin/subscription-plans');

export const createSubscriptionPlan = (data: SubscriptionPlanFormData) =>
  api.post<{ data: SubscriptionPlanAdmin }>('/admin/subscription-plans', data);

export const updateSubscriptionPlan = (id: string, data: SubscriptionPlanFormData) =>
  api.put<{ data: SubscriptionPlanAdmin }>(`/admin/subscription-plans/${id}`, data);

export const deleteSubscriptionPlan = (id: string) =>
  api.delete(`/admin/subscription-plans/${id}`);

// --- Tenant Subscriptions (Super Admin) ---

export interface TenantSubscription {
  id: string;
  tenant_id: string;
  subscription_plan_id: string;
  user_id: string;
  status: string;
  starts_at: string;
  ends_at: string;
  amount_paid: string;
  payment_status_description: string | null;
  confirmation_code: string | null;
  payment_method_used: string | null;
  paid_at: string | null;
  created_at: string;
  plan?: { id: string; name: string; price: string; billing_cycle_days: number };
  user?: { id: string; name: string; email: string };
  invoice_number?: string | null;
  payment_method?: 'pesapal' | 'bank_transfer' | null;
  invoice_due_date?: string | null;
  payment_proof_path?: string | null;
  payment_confirmed_at?: string | null;
  payment_confirmed_by?: string | null;
  payment_reference?: string | null;
}

export const getTenantSubscriptions = (tenantId: string, params?: { page?: number }) =>
  api.get(`/admin/tenants/${tenantId}/subscriptions`, { params });

export const extendTenantSubscription = (tenantId: string, data: { plan_id: string; days: number }) =>
  api.post(`/admin/tenants/${tenantId}/subscriptions/extend`, data);

// --- SMS Purchases (Super Admin) ---

export interface SmsPurchase {
  id: string;
  tenant_id: string;
  user_id: string;
  sms_quantity: number;
  price_per_sms: string;
  total_amount: string;
  package_name: string;
  status: 'pending' | 'completed' | 'failed';
  order_tracking_id: string | null;
  confirmation_code: string | null;
  payment_method_used: string | null;
  completed_at: string | null;
  created_at: string;
  tenant?: { id: string; name: string };
  user?: { id: string; name: string; email: string };
}

export const getAdminSmsPurchases = (params?: { status?: string; tenant_id?: string; page?: number }) =>
  api.get('/admin/sms-purchases', { params });

// --- Currencies (Super Admin) ---

export interface Currency {
  id: string;
  code: string;
  name: string;
  symbol: string | null;
  is_active: boolean;
  sort_order: number;
  created_at: string;
}

export interface CurrencyFormData {
  code: string;
  name: string;
  symbol: string;
  is_active: boolean;
  sort_order: number | string;
}

export const getAdminCurrencies = () =>
  api.get<{ data: Currency[] }>('/admin/currencies');

export const createCurrency = (data: CurrencyFormData) =>
  api.post<{ data: Currency }>('/admin/currencies', data);

export const updateCurrency = (id: string, data: CurrencyFormData) =>
  api.put<{ data: Currency }>(`/admin/currencies/${id}`, data);

export const deleteCurrency = (id: string) =>
  api.delete(`/admin/currencies/${id}`);

// Public: active currencies for dropdowns
export const getActiveCurrencies = () =>
  api.get<{ data: Currency[] }>('/currencies');

// --- Confirm Subscription Payment (Super Admin) ---

export const confirmSubscriptionPayment = (subscriptionId: string, paymentReference?: string) =>
  api.post(`/admin/subscriptions/${subscriptionId}/confirm-payment`, {
    payment_reference: paymentReference || null,
  });

// --- Platform Settings (Super Admin) ---

export interface PlatformSettings {
  platform_bank_name: string;
  platform_bank_account_name: string;
  platform_bank_account_number: string;
  platform_bank_branch: string;
  platform_payment_instructions: string;
  // Email templates
  welcome_email_subject: string;
  welcome_email_body: string;
  reset_password_email_subject: string;
  reset_password_email_body: string;
  new_tenant_email_subject: string;
  new_tenant_email_body: string;
  sms_activation_email_subject: string;
  sms_activation_email_body: string;
}

export const getPlatformSettings = () =>
  api.get<{ data: PlatformSettings }>('/admin/platform-settings');

export const updatePlatformSettings = (data: Partial<PlatformSettings>) =>
  api.put<{ message: string; data: PlatformSettings }>('/admin/platform-settings', data);
