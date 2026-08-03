import api from './axios';
import type {
  CatalogGroup, CouponValidateResult, ProductAddonRow, PortalConfigGroup,
  PortalTldRow, DomainAddonRow, OrderConfigOption,
} from './portal';

// Admin ordering on behalf of a client (WHMCS-style "Add New Order").
// Same shapes as the portal storefront, but staff name the client explicitly.

export const getOrderCatalog = () =>
  api.get<{ data: CatalogGroup[] }>('/orders/catalog');

export const getOrderDomainTlds = () =>
  api.get<{ data: PortalTldRow[] }>('/orders/domain-tlds');

export const getOrderDomainAddons = () =>
  api.get<{ data: DomainAddonRow[] }>('/orders/domain-addons');

export const getOrderProductAddons = (productId: string) =>
  api.get<{ data: ProductAddonRow[] }>(`/orders/products/${productId}/addons`);

export const getOrderConfigOptions = (productId: string) =>
  api.get<{ data: PortalConfigGroup[] }>(`/orders/products/${productId}/config-options`);

export const validateOrderCoupon = (client_id: string, code: string, product_service_id: string) =>
  api.post<CouponValidateResult>('/orders/coupons/validate', { client_id, code, product_service_id });

export interface PlaceOrderPayload {
  client_id: string;
  product_service_id: string;
  label?: string;
  domain_mode?: 'register' | 'transfer' | 'existing';
  auth_info?: string;
  years?: number;
  addons?: string[];
  product_addon_ids?: string[];
  config_options?: OrderConfigOption[];
  coupon_code?: string;
}

export interface PlaceOrderResult {
  data: { subscription_id: string; document_id: string; document_number: string; total: number };
  message: string;
}

export const placeOrder = (payload: PlaceOrderPayload) =>
  api.post<PlaceOrderResult>('/orders', payload);
