import api from './axios';

export interface SubscriptionPlan {
  id: string;
  name: string;
  slug: string;
  description: string | null;
  price: string;
  billing_cycle_days: number;
  features: string[] | null;
  is_active: boolean;
  sort_order: number;
}

export interface TenantSubscription {
  id: string;
  tenant_id: string;
  subscription_plan_id: string;
  user_id: string | null;
  status: 'pending' | 'active' | 'expired' | 'cancelled';
  starts_at: string | null;
  ends_at: string | null;
  amount_paid: string;
  order_tracking_id: string | null;
  confirmation_code: string | null;
  payment_method_used: string | null;
  paid_at: string | null;
  created_at: string;
  plan?: SubscriptionPlan;
  invoice_number?: string | null;
  payment_method?: 'pesapal' | 'bank_transfer' | null;
  invoice_due_date?: string | null;
  payment_proof_path?: string | null;
  payment_confirmed_at?: string | null;
  payment_reference?: string | null;
  pesapal_redirect_url?: string | null;
}

export interface SubscriptionStatus {
  subscription_status: 'trial' | 'subscribed' | 'expired' | 'deactivated';
  days_remaining: number;
  trial_ends_at: string | null;
  active_subscription: TenantSubscription | null;
}

export interface BankDetails {
  bank_name: string;
  bank_account_name: string;
  bank_account_number: string;
  bank_branch: string;
  payment_instructions: string;
}

export interface CheckoutResponse {
  subscription_id: string;
  payment_method: 'pesapal' | 'bank_transfer';
  invoice_number?: string;
  invoice_due_date?: string;
  amount?: string;
  bank_details?: BankDetails;
  redirect_url: string | null;
  order_tracking_id?: string | null;
}

export const getSubscriptionPlans = () =>
  api.get<{ data: SubscriptionPlan[] }>('/subscription/plans');

export const getPublicPlans = () =>
  api.get<{ data: SubscriptionPlan[] }>('/plans');

export const getSubscriptionCurrent = () =>
  api.get<{ data: SubscriptionStatus }>('/subscription/current');

export const subscriptionCheckout = (planId: string, paymentMethod: 'pesapal' | 'bank_transfer' = 'pesapal') =>
  api.post<{ message: string; data: CheckoutResponse }>('/subscription/checkout', {
    plan_id: planId,
    payment_method: paymentMethod,
  });

export const getSubscriptionHistory = (params?: { page?: number }) =>
  api.get('/subscription/history', { params });

export const checkSubscriptionPaymentStatus = (subscriptionId: string) =>
  api.get(`/subscription/${subscriptionId}/status`);

export const downloadSubscriptionInvoice = (subscriptionId: string) =>
  api.get(`/subscription/${subscriptionId}/invoice`, { responseType: 'blob' });

export const uploadPaymentProof = (subscriptionId: string, file: File) => {
  const formData = new FormData();
  formData.append('proof', file);
  return api.post(`/subscription/${subscriptionId}/proof`, formData, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });
};
