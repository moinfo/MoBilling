import api from './axios';

export interface BillCategory {
  id: string;
  parent_id: string | null;
  name: string;
  billing_cycle: string | null;
  is_active: boolean;
  children?: BillCategory[];
  created_at: string;
}

export interface BillCategoryFormData {
  parent_id?: string | null;
  name: string;
  billing_cycle?: string | null;
  is_active?: boolean;
}

export const getBillCategories = () =>
  api.get<{ data: BillCategory[] }>('/bill-categories');

export const createBillCategory = (data: BillCategoryFormData) =>
  api.post('/bill-categories', data);

export const updateBillCategory = (id: string, data: BillCategoryFormData) =>
  api.put(`/bill-categories/${id}`, data);

export const deleteBillCategory = (id: string) =>
  api.delete(`/bill-categories/${id}`);
