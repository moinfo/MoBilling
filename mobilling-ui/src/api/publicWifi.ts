import api from './axios';

export interface PublicWifiPlan {
  id: string;
  name: string;
  duration_value: number | null;
  duration_unit: 'hours' | 'days' | 'weeks' | null;
  data_cap_mb: number | null;
  price: number;
}

export interface PublicWifiCheckoutInfo {
  router: { id: string; name: string };
  tenant: { name: string | null; logo_url: string | null; currency: string };
  plans: PublicWifiPlan[];
}

export interface PublicWifiPurchaseStatus {
  id: string;
  status: 'pending' | 'completed' | 'failed';
  hotspot_username: string | null;
  hotspot_password: string | null;
  plan: { duration_value: number | null; duration_unit: 'hours' | 'days' | 'weeks' | null; data_cap_mb: number | null } | null;
  local_login_host: string | null;
}

export const getPublicWifiCheckoutInfo = (routerId: string) =>
  api.get<{ data: PublicWifiCheckoutInfo }>(`/public/wifi/${routerId}`);

export const submitPublicWifiCheckout = (routerId: string, data: { phone: string; name?: string; wifi_plan_id: string }) =>
  api.post<{ data: { purchase_id: string; redirect_url: string | null } }>(`/public/wifi/${routerId}/checkout`, data);

export const getPublicWifiPurchaseStatus = (purchaseId: string) =>
  api.get<{ data: PublicWifiPurchaseStatus }>(`/public/wifi/purchases/${purchaseId}`);

export interface PublicWifiBalance {
  hotspot_username: string;
  data_cap_mb: number | null;
  data_used_mb: number | null;
  data_remaining_mb: number | null;
  duration_seconds: number | null;
  time_used_seconds: number | null;
  time_remaining_seconds: number | null;
  router_reachable: boolean;
}

export const getPublicWifiBalance = (routerId: string, code: string) =>
  api.get<{ data: PublicWifiBalance }>(`/public/wifi/${routerId}/balance`, { params: { code } });
