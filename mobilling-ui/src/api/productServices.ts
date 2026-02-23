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
  is_active: boolean;
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
  is_active: boolean;
}

export const getProductServices = (params?: { search?: string; type?: string; page?: number; active_only?: boolean }) =>
  api.get('/product-services', { params });

export const getProductService = (id: string) =>
  api.get<{ data: ProductService }>(`/product-services/${id}`);

export const createProductService = (data: ProductServiceFormData) =>
  api.post('/product-services', data);

export const updateProductService = (id: string, data: ProductServiceFormData) =>
  api.put(`/product-services/${id}`, data);

export const deleteProductService = (id: string) =>
  api.delete(`/product-services/${id}`);
