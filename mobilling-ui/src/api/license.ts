import api from './axios';

export interface LicenseStatus {
  license_key: string | null;
  status: 'active' | 'inactive';
  expires_at: string | null;
  last_checked_at: string | null;
  app_version: string | null;
}

export interface LatestRelease {
  version: string;
  changelog: string | null;
  download_url: string | null;
  released_at: string;
}

export const getLicenseStatus = () => api.get<{ data: LicenseStatus }>('/license-status');
export const getLatestRelease = () => api.get<{ data: LatestRelease | null }>('/releases/latest');

export interface LicensePurchaseCheckoutData {
  customer_name: string;
  customer_email: string;
  customer_phone?: string;
  product: 'lite' | 'reseller' | 'general';
  billing_period: 'monthly' | 'quarterly' | 'semi_annual' | 'annual' | 'perpetual';
}

export interface LicensePurchaseCheckout {
  purchase_id: string;
  redirect_url: string | null;
  order_tracking_id: string | null;
  amount: number;
  product: string;
  billing_period: string;
}

export interface LicensePurchaseStatus {
  id: string;
  status: 'pending' | 'completed' | 'failed';
  product: string;
  billing_period: string;
  amount: string;
  license: { license_key: string; expires_at: string | null } | null;
}

export const checkoutLicensePurchase = (data: LicensePurchaseCheckoutData) =>
  api.post<{ data: LicensePurchaseCheckout }>('/license-purchases', data);
export const getLicensePurchaseStatus = (id: string) =>
  api.get<{ data: LicensePurchaseStatus }>(`/license-purchases/${id}`);
