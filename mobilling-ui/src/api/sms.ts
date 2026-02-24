import api from './axios';

export interface SmsPackage {
  id: string;
  name: string;
  price_per_sms: string;
  min_quantity: number;
  max_quantity: number | null;
  is_active: boolean;
  sort_order: number;
}

export interface SmsBalance {
  sms_balance: number | null;
  message?: string;
  error?: string;
}

export interface SmsPurchase {
  id: string;
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
}

export interface CheckoutResponse {
  purchase_id: string;
  redirect_url: string | null;
  order_tracking_id: string | null;
}

export const getSmsPackages = () =>
  api.get<{ data: SmsPackage[] }>('/sms/packages');

export const getSmsBalance = () =>
  api.get<{ data: SmsBalance }>('/sms/balance');

export const smsCheckout = (sms_quantity: number) =>
  api.post<{ message: string; data: CheckoutResponse }>('/sms/checkout', { sms_quantity });

export const checkPurchaseStatus = (purchaseId: string) =>
  api.get<{ data: { id: string; status: string; payment_status_description: string | null; confirmation_code: string | null; sms_quantity: number; total_amount: string } }>(`/sms/purchases/${purchaseId}/status`);

export const getSmsPurchaseHistory = (params?: { page?: number }) =>
  api.get('/sms/purchases', { params });
