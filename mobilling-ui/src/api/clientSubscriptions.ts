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

export const getClientSubscriptions = (params?: {
  search?: string;
  client_id?: string;
  status?: string;
  page?: number;
  per_page?: number;
}) => api.get('/client-subscriptions', { params });

export const getClientSubscription = (id: string) =>
  api.get<{ data: ClientSubscription }>(`/client-subscriptions/${id}`);

export const createClientSubscription = (data: ClientSubscriptionFormData) =>
  api.post('/client-subscriptions', data);

export const updateClientSubscription = (id: string, data: ClientSubscriptionFormData) =>
  api.put(`/client-subscriptions/${id}`, data);

export const deleteClientSubscription = (id: string) =>
  api.delete(`/client-subscriptions/${id}`);
