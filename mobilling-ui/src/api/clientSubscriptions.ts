import api from './axios';

export interface ClientSubscription {
  id: string;
  client_id: string;
  client_name?: string;
  product_service_id: string;
  product_service_name?: string;
  billing_cycle?: string;
  price?: string;
  label: string | null;
  quantity: number;
  start_date: string;
  expire_date?: string;
  status: 'active' | 'cancelled' | 'suspended';
  metadata: Record<string, unknown> | null;
  created_at: string;
}

export interface ClientSubscriptionFormData {
  client_id: string;
  product_service_id: string;
  label: string;
  quantity: number;
  start_date: string;
  status: string;
}

export interface BulkSubscriptionItem {
  product_service_id: string;
  label: string;
  quantity: number;
}

export interface BulkSubscriptionFormData {
  client_id: string;
  start_date: string;
  status: string;
  items: BulkSubscriptionItem[];
}

export const getClientSubscriptions = (params?: {
  search?: string;
  client_id?: string;
  status?: string;
  sort_by?: string;
  sort_dir?: 'asc' | 'desc';
  page?: number;
  per_page?: number;
}) => api.get('/client-subscriptions', { params });

export const getClientSubscription = (id: string) =>
  api.get<{ data: ClientSubscription }>(`/client-subscriptions/${id}`);

export const createClientSubscription = (data: ClientSubscriptionFormData) =>
  api.post('/client-subscriptions', data);

export const createBulkSubscription = (data: BulkSubscriptionFormData) =>
  api.post('/client-subscriptions/bulk', data);

export const updateClientSubscription = (id: string, data: ClientSubscriptionFormData) =>
  api.put(`/client-subscriptions/${id}`, data);

export const deleteClientSubscription = (id: string) =>
  api.delete(`/client-subscriptions/${id}`);

export const updateExpireDate = (id: string, expire_date: string) =>
  api.patch(`/client-subscriptions/${id}/expire-date`, { expire_date });

export const generateInvoiceFromSubscription = (id: string) =>
  api.post<{ message: string; data: { document_id: string; document_number: string } }>(`/client-subscriptions/${id}/generate-invoice`);
