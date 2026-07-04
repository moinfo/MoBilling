import api from './axios';

export interface Coupon {
  id: string;
  code: string;
  description: string | null;
  type: 'percent' | 'fixed';
  value: number;
  applies_to: 'all' | 'product';
  max_uses: number | null;
  uses: number;
  min_order: number | null;
  starts_at: string | null;
  expires_at: string | null;
  recurring: boolean;
  is_active: boolean;
  redemptions_count: number;
  last_used_at: string | null;
  product_service_ids: string[];
  products: { id: string; name: string }[];
}

export interface CouponFormData {
  code: string;
  description?: string;
  type: 'percent' | 'fixed';
  value: number;
  applies_to: 'all' | 'product';
  max_uses?: number | null;
  min_order?: number | null;
  starts_at?: string | null;
  expires_at?: string | null;
  recurring: boolean;
  is_active: boolean;
  product_service_ids: string[];
}

export interface CouponRedemption {
  id: string;
  client_id: string;
  client_name: string | null;
  document_id: string | null;
  discount_amount: number;
  created_at: string;
}

export const getCoupons = (params?: { search?: string; active_only?: boolean }) =>
  api.get<{ data: Coupon[] }>('/coupons', { params });

export const createCoupon = (data: CouponFormData) =>
  api.post('/coupons', data);

export const updateCoupon = (id: string, data: CouponFormData) =>
  api.put(`/coupons/${id}`, data);

export const deleteCoupon = (id: string) =>
  api.delete(`/coupons/${id}`);

export const getCouponRedemptions = (id: string) =>
  api.get<{ data: CouponRedemption[] }>(`/coupons/${id}/redemptions`);
