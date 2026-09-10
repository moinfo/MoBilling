import api from './axios';

export interface WifiVoucherPurchase {
  id: string;
  router?: { id: string; name: string };
  plan?: { id: string; name: string };
  customer_phone: string;
  customer_name: string | null;
  amount: string;
  status: 'pending' | 'completed' | 'failed';
  payment_method_used: string | null;
  hotspot_username: string | null;
  hotspot_password: string | null;
  voucher_expires_at: string | null;
  completed_at: string | null;
  created_at: string;
}

export interface ManualWifiVoucherSalePayload {
  mikrotik_router_id: string;
  wifi_plan_id: string;
  customer_phone: string;
  customer_name?: string;
  payment_method: 'cash' | 'mpesa' | 'bank' | 'other';
}

export const getWifiVoucherPurchases = (params?: {
  mikrotik_router_id?: string;
  status?: string;
  search?: string;
  page?: number;
  per_page?: number;
}) => api.get('/wifi-voucher-purchases', { params });

export const createManualWifiVoucherSale = (data: ManualWifiVoucherSalePayload) =>
  api.post<{ data: WifiVoucherPurchase }>('/wifi-voucher-purchases', data);

export interface WifiVoucherUsage {
  data_cap_mb: number | null;
  data_used_mb: number | null;
  data_remaining_mb: number | null;
  duration_seconds: number | null;
  time_used_seconds: number | null;
  time_remaining_seconds: number | null;
  router_reachable: boolean;
}

export const getWifiVoucherPurchaseUsage = (id: string) =>
  api.get<{ data: WifiVoucherUsage }>(`/wifi-voucher-purchases/${id}/usage`);
