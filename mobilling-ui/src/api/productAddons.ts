import api from './axios';

export interface ProductAddon {
  id: string;
  name: string;
  description: string | null;
  price: number;
  billing_cycle: 'once' | 'monthly' | 'quarterly' | 'half_yearly' | 'yearly';
  tax_percent: number;
  is_active: boolean;
  product_service_ids: string[];
  products: { id: string; name: string }[];
}

export interface ProductAddonFormData {
  name: string;
  description?: string;
  price: number;
  billing_cycle: string;
  tax_percent: number;
  is_active: boolean;
  product_service_ids: string[];
}

export const getProductAddons = (params?: { search?: string; active_only?: boolean }) =>
  api.get<{ data: ProductAddon[] }>('/product-addons', { params });

export const createProductAddon = (data: ProductAddonFormData) =>
  api.post('/product-addons', data);

export const updateProductAddon = (id: string, data: ProductAddonFormData) =>
  api.put(`/product-addons/${id}`, data);

export const deleteProductAddon = (id: string) =>
  api.delete(`/product-addons/${id}`);
