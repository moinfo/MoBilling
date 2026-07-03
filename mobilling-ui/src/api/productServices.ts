import api from './axios';

export interface ProductService {
  id: string;
  type: 'product' | 'service';
  name: string;
  code: string | null;
  description: string | null;
  price: string;
  tax_percent: string;
  unit: string;
  category: string | null;
  billing_cycle: string | null;
  is_active: boolean;
  provisioning_type: 'none' | 'whm_cpanel';
  server_id: string | null;
  cpanel_package: string | null;
  auto_provision: boolean;
  portal_visible: boolean;
  created_at: string;
}

export interface ProductServiceFormData {
  type: 'product' | 'service';
  name: string;
  code: string;
  description: string;
  price: number;
  tax_percent: number;
  unit: string;
  category: string;
  billing_cycle: string;
  is_active: boolean;
  provisioning_type?: 'none' | 'whm_cpanel';
  server_id?: string | null;
  cpanel_package?: string;
  auto_provision?: boolean;
  portal_visible?: boolean;
}

export const getProductServices = (params?: { search?: string; type?: string; page?: number; active_only?: boolean; per_page?: number }) =>
  api.get('/product-services', { params });

export const getProductService = (id: string) =>
  api.get<{ data: ProductService }>(`/product-services/${id}`);

export const createProductService = (data: ProductServiceFormData) =>
  api.post('/product-services', data);

export const updateProductService = (id: string, data: ProductServiceFormData) =>
  api.put(`/product-services/${id}`, data);

export const deleteProductService = (id: string) =>
  api.delete(`/product-services/${id}`);
